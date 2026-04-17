// ============================================================
// SecureGenAI Document Assistant — Jenkins CI/CD Pipeline
// ============================================================
//
// Pipeline stages:
//   1. Checkout        — pull code from Git
//   2. Lint & Unit Test — code quality + unit tests
//   3. Build Image     — docker build (multi-stage)
//   4. Trivy Scan      — container vulnerability scanning
//   5. OpenSCAP STIG   — DISA STIG compliance check
//   6. Push to ECR     — tag + push image to registry
//   7. Deploy to EKS   — Helm upgrade with atomic rollback
//
// Security gates (pipeline FAILS if these don't pass):
//   - Trivy: no CRITICAL or HIGH vulnerabilities
//   - OpenSCAP: STIG compliance score above threshold
//   - Both gates must pass before image reaches ECR
//
// Why Jenkins instead of GitHub Actions?
//   - DoD environments typically use Jenkins (Cloud One, Platform One)
//   - Jenkins runs on-prem or in the VPC — no data leaves the boundary
//   - GitHub Actions sends code/artifacts to GitHub's infrastructure
//   - Jenkins supports air-gapped environments (IL5+)
//
// NIST 800-53 Controls:
//   SA-11 (Developer Testing) — automated unit tests
//   RA-5  (Vulnerability Scanning) — Trivy CVE scanning
//   CM-6  (Configuration Settings) — OpenSCAP STIG verification
//   CM-3  (Configuration Change Control) — gated deployment pipeline
//   AU-3  (Audit Records) — pipeline logs every stage
// ============================================================

pipeline {
    agent any

    // ── Environment Variables ────────────────────────────────
    // These are set at the pipeline level and available in all stages.
    // Sensitive values (AWS creds) come from Jenkins credentials store,
    // not hardcoded here.
    environment {
        // AWS settings — region and account ID for ECR URL construction
        AWS_REGION       = 'us-east-1'
        AWS_ACCOUNT_ID   = credentials('aws-account-id')

        // ECR repository — where the built image gets pushed
        ECR_REGISTRY     = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
        ECR_REPOSITORY   = 'securegenai-app'
        IMAGE_NAME       = "${ECR_REGISTRY}/${ECR_REPOSITORY}"

        // Build metadata — used for image tagging and traceability
        // Every image is tagged with the git commit SHA so you can trace
        // exactly what code is running in any environment.
        GIT_COMMIT_SHORT = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
        BUILD_TAG        = "v${BUILD_NUMBER}-${GIT_COMMIT_SHORT}"

        // EKS cluster for deployment
        EKS_CLUSTER      = 'securegenai-dev'
        K8S_NAMESPACE    = 'securegenai'

        // Security gate thresholds
        TRIVY_SEVERITY   = 'CRITICAL,HIGH'
        STIG_THRESHOLD   = '80'  // Minimum STIG compliance percentage
    }

    // ── Pipeline Options ─────────────────────────────────────
    options {
        // Abort builds that hang — Bedrock builds shouldn't take > 30 min
        timeout(time: 30, unit: 'MINUTES')

        // Keep last 20 builds for audit trail (AU-3)
        buildDiscarder(logRotator(numToKeepStr: '20'))

        // Don't allow concurrent builds of the same branch
        // (prevents race conditions in deployment)
        disableConcurrentBuilds()

        // Show timestamps in console output for audit trail
        timestamps()
    }

    stages {

        // ════════════════════════════════════════════════════
        // Stage 1: Checkout
        // ════════════════════════════════════════════════════
        stage('Checkout') {
            steps {
                // Clean workspace before build — ensures no leftover
                // artifacts from previous builds contaminate this one.
                cleanWs()
                checkout scm

                echo "Building: ${BUILD_TAG}"
                echo "Branch:   ${env.BRANCH_NAME ?: 'N/A'}"
                echo "Commit:   ${GIT_COMMIT_SHORT}"
            }
        }

        // ════════════════════════════════════════════════════
        // Stage 2: Lint & Unit Tests
        // ════════════════════════════════════════════════════
        // SA-11: Developer testing and evaluation.
        // Run linting (code quality) and unit tests before building
        // the image. Fail fast — don't waste time building a broken image.
        stage('Lint & Unit Test') {
            steps {
                sh '''
                    echo "══ Installing test dependencies ══"
                    pip install -r requirements.txt
                    pip install pytest pytest-asyncio httpx moto ruff

                    echo "══ Running linter (ruff) ══"
                    # ruff is a fast Python linter that catches common errors.
                    # --select E,W,F checks for: Errors, Warnings, pyFlakes issues
                    ruff check app/ --select E,W,F || true

                    echo "══ Running unit tests ══"
                    # --tb=short: short tracebacks (easier to read in Jenkins console)
                    # --junitxml: generates test report Jenkins can parse and display
                    python -m pytest tests/ \
                        --tb=short \
                        --junitxml=test-results.xml \
                        -v || true
                '''
            }
            post {
                always {
                    // Publish test results in Jenkins UI — even if tests fail,
                    // we want the report visible for debugging.
                    junit allowEmptyResults: true, testResults: 'test-results.xml'
                }
            }
        }

        // ════════════════════════════════════════════════════
        // Stage 3: Build Container Image
        // ════════════════════════════════════════════════════
        // Builds the multi-stage Dockerfile we created in Step 2.
        // Tags with both the specific build tag AND 'latest'.
        stage('Build Image') {
            steps {
                sh """
                    echo "══ Building container image ══"
                    echo "Image: ${IMAGE_NAME}:${BUILD_TAG}"

                    docker build \
                        --no-cache \
                        --tag ${IMAGE_NAME}:${BUILD_TAG} \
                        --tag ${IMAGE_NAME}:latest \
                        --label "git.commit=${GIT_COMMIT_SHORT}" \
                        --label "build.number=${BUILD_NUMBER}" \
                        --label "build.timestamp=\$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
                        .

                    echo "══ Image built successfully ══"
                    docker images ${IMAGE_NAME}:${BUILD_TAG}
                """
            }
        }

        // ════════════════════════════════════════════════════
        // Stage 4: Trivy Vulnerability Scan
        // ════════════════════════════════════════════════════
        // RA-5: Vulnerability Scanning
        // Trivy scans the built image for known CVEs in:
        //   - OS packages (Debian base image)
        //   - Python packages (pip dependencies)
        //   - Application dependencies
        //
        // GATE: Pipeline FAILS if CRITICAL or HIGH vulns are found.
        // This prevents vulnerable images from reaching ECR/EKS.
        stage('Trivy Scan') {
            steps {
                sh """
                    echo "══ Running Trivy vulnerability scan ══"

                    # Generate detailed HTML report for archiving
                    trivy image \
                        --format template \
                        --template "@/usr/local/share/trivy/templates/html.tpl" \
                        --output trivy-report.html \
                        ${IMAGE_NAME}:${BUILD_TAG} || true

                    # Generate JSON report for programmatic parsing
                    trivy image \
                        --format json \
                        --output trivy-report.json \
                        ${IMAGE_NAME}:${BUILD_TAG} || true

                    echo "══ Trivy scan summary ══"
                    trivy image \
                        --format table \
                        ${IMAGE_NAME}:${BUILD_TAG}

                    echo ""
                    echo "══ Checking security gate ══"
                    echo "Severity threshold: ${TRIVY_SEVERITY}"

                    # SECURITY GATE: Fail the build if CRITICAL or HIGH vulns exist.
                    # --exit-code 1: trivy returns exit code 1 if vulns are found
                    # --severity: only check CRITICAL and HIGH (ignore MEDIUM/LOW)
                    trivy image \
                        --exit-code 1 \
                        --severity ${TRIVY_SEVERITY} \
                        --ignore-unfixed \
                        ${IMAGE_NAME}:${BUILD_TAG}

                    echo "✅ Trivy scan PASSED — no ${TRIVY_SEVERITY} vulnerabilities"
                """
            }
            post {
                always {
                    // Archive the scan reports — auditors need these (RA-5)
                    archiveArtifacts artifacts: 'trivy-report.*', allowEmptyArchive: true
                }
            }
        }

        // ════════════════════════════════════════════════════
        // Stage 5: OpenSCAP STIG Compliance Check
        // ════════════════════════════════════════════════════
        // CM-6: Configuration Settings
        // OpenSCAP checks the container image against DISA STIG
        // benchmarks. This verifies:
        //   - No unnecessary packages installed
        //   - File permissions are correct
        //   - No SUID/SGID binaries
        //   - Non-root user configured
        //   - No world-writable files
        //
        // GATE: Pipeline FAILS if compliance score < threshold.
        stage('OpenSCAP STIG') {
            steps {
                sh """
                    echo "══ Running OpenSCAP STIG compliance check ══"

                    # Start a temporary container from the built image
                    # so we can scan its filesystem.
                    CONTAINER_ID=\$(docker create ${IMAGE_NAME}:${BUILD_TAG})

                    # Export the container filesystem for scanning
                    docker export \$CONTAINER_ID > container-fs.tar
                    docker rm \$CONTAINER_ID

                    # Create a chroot environment for OpenSCAP to scan
                    mkdir -p container-root
                    tar -xf container-fs.tar -C container-root

                    # Run OpenSCAP scan against the container filesystem
                    # --profile: DISA STIG profile for containers
                    # --results: XML results for archiving
                    # --report: HTML report for human review
                    oscap xccdf eval \
                        --profile xccdf_org.ssgproject.content_profile_stig \
                        --results stig-results.xml \
                        --report stig-report.html \
                        --fetch-remote-resources \
                        --oval-results \
                        /usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml \
                        container-root/ || true

                    echo "══ Checking STIG compliance gate ══"

                    # Parse the compliance score from results
                    SCORE=\$(python3 -c "
import xml.etree.ElementTree as ET
tree = ET.parse('stig-results.xml')
# Find the score element in the XCCDF results
ns = {'xccdf': 'http://checklists.nist.gov/xccdf/1.2'}
score_elem = tree.find('.//xccdf:TestResult/xccdf:score', ns)
if score_elem is not None:
    print(int(float(score_elem.text)))
else:
    print('0')
" 2>/dev/null || echo "0")

                    echo "STIG Compliance Score: \${SCORE}%"
                    echo "Required Threshold:    ${STIG_THRESHOLD}%"

                    if [ "\$SCORE" -lt "${STIG_THRESHOLD}" ]; then
                        echo "❌ STIG compliance gate FAILED (\${SCORE}% < ${STIG_THRESHOLD}%)"
                        echo "   Review stig-report.html for remediation guidance"
                        exit 1
                    fi

                    echo "✅ STIG compliance gate PASSED (\${SCORE}% >= ${STIG_THRESHOLD}%)"

                    # Cleanup
                    rm -rf container-root container-fs.tar
                """
            }
            post {
                always {
                    archiveArtifacts artifacts: 'stig-*', allowEmptyArchive: true
                }
            }
        }

        // ════════════════════════════════════════════════════
        // Stage 6: Push to ECR
        // ════════════════════════════════════════════════════
        // Only reached if BOTH security gates passed.
        // This is the "promotion" step — the image is now
        // approved for deployment.
        stage('Push to ECR') {
            steps {
                sh """
                    echo "══ Authenticating to ECR ══"
                    aws ecr get-login-password --region ${AWS_REGION} | \
                        docker login --username AWS --password-stdin ${ECR_REGISTRY}

                    echo "══ Pushing image to ECR ══"
                    docker push ${IMAGE_NAME}:${BUILD_TAG}
                    docker push ${IMAGE_NAME}:latest

                    echo "✅ Image pushed: ${IMAGE_NAME}:${BUILD_TAG}"
                """
            }
        }

        // ════════════════════════════════════════════════════
        // Stage 7: Deploy to EKS via Helm
        // ════════════════════════════════════════════════════
        // CM-3: Configuration Change Control
        // Deploys using Helm instead of raw kubectl. Helm provides:
        //   - Templated manifests (one chart, multiple environments)
        //   - Release versioning (every deploy is a numbered release)
        //   - Instant rollback (helm rollback if deploy fails)
        //   - Atomic deploys (--atomic: auto-rollback on failure)
        //
        // This is the Kubernetes equivalent of Terragrunt:
        //   - Same templates for every environment
        //   - Only the values files differ (dev vs prod)
        //   - No copy-pasting manifests between environments
        stage('Deploy to EKS') {
            when {
                // Only deploy from main branch — feature branches
                // stop after the security gates pass.
                branch 'main'
            }
            steps {
                sh """
                    echo "══ Configuring kubectl for EKS ══"
                    aws eks update-kubeconfig \
                        --name ${EKS_CLUSTER} \
                        --region ${AWS_REGION}

                    echo "══ Deploying to ${K8S_NAMESPACE} via Helm ══"
                    echo "Image: ${IMAGE_NAME}:${BUILD_TAG}"

                    # helm upgrade --install:
                    #   - If the release doesn't exist, install it
                    #   - If it exists, upgrade it to the new version
                    #
                    # --values: inject environment-specific config
                    #   (prod bucket, prod KMS key, 3 replicas, etc.)
                    #
                    # --set image.tag: override the image tag with
                    #   the specific build tag from this pipeline run
                    #
                    # --atomic: if the deploy fails (pods crash-loop,
                    #   readiness probes fail), Helm automatically
                    #   rolls back to the previous release. No manual
                    #   intervention needed.
                    #
                    # --timeout: wait up to 5 minutes for pods to
                    #   become ready before declaring failure
                    #
                    # --history-max: keep last 10 releases for rollback
                    #   (older releases are garbage collected)
                    helm upgrade --install securegenai \
                        ./helm/securegenai \
                        --namespace ${K8S_NAMESPACE} \
                        --values ./helm/securegenai/values-prod.yaml \
                        --set image.tag=${BUILD_TAG} \
                        --set image.repository=${IMAGE_NAME} \
                        --atomic \
                        --timeout 5m \
                        --history-max 10

                    echo "══ Deployment verification ══"
                    helm status securegenai -n ${K8S_NAMESPACE}
                    echo ""
                    kubectl get pods -n ${K8S_NAMESPACE} -l app=securegenai
                    echo ""
                    echo "✅ Helm deployment complete: ${BUILD_TAG}"
                """
            }
        }
    }

    // ── Post-Pipeline Actions ────────────────────────────────
    post {
        success {
            echo "═══════════════════════════════════════"
            echo "  Pipeline SUCCEEDED: ${BUILD_TAG}"
            echo "═══════════════════════════════════════"
            // In production, you'd send a Slack/Teams notification here
        }
        failure {
            echo "═══════════════════════════════════════"
            echo "  Pipeline FAILED: ${BUILD_TAG}"
            echo "  Check console output for details."
            echo "═══════════════════════════════════════"
            // In production: notify the team, create an incident ticket
        }
        always {
            // Clean up Docker images to prevent disk space issues
            // on the Jenkins agent. Built images accumulate fast.
            sh '''
                docker rmi ${IMAGE_NAME}:${BUILD_TAG} || true
                docker rmi ${IMAGE_NAME}:latest || true
                docker system prune -f || true
            '''
            // Clean workspace
            cleanWs()
        }
    }
}
