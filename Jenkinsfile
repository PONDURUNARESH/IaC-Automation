pipeline {
    agent any

    options { timestamps() }

    triggers {
        pollSCM('H/2 * * * *')
    }

    stages {

        stage('Checkout') {
            steps {
                git branch: 'main',
                    url: 'https://github.com/PONDURUNARESH/IaC-Automation.git'
            }
        }

        stage('Terraform Init') {
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'aws-terraform'
                ]]) {
                    bat '''
                    terraform --version
                    terraform init -upgrade
                    '''
                }
            }
        }

        stage('Terraform Validate') {
            steps {
                bat 'terraform validate'
            }
        }

        stage('Terraform Plan') {
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'aws-terraform'
                ]]) {
                    bat 'terraform plan -out=tfplan'
                }
            }
        }

        stage('Manual Approval - Apply') {
            steps {
                timeout(time: 15, unit: 'MINUTES') {
                    input message: "Do you want to APPLY the Terraform changes?",
                          ok: "Yes, Apply"
                }
            }
        }

        stage('Terraform Apply') {
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'aws-terraform'
                ]]) {
                    bat 'terraform apply -auto-approve tfplan'
                }
            }
        }

        // ✅ IMPORTANT: Archive PEM AFTER Apply
        stage('Archive PEM Key') {
            steps {
                archiveArtifacts artifacts: '*.pem', fingerprint: true
            }
        }

        // ── NEW: Verify Monitoring Stack is healthy after every deploy ────────
        stage('Verify Monitoring Stack') {
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'aws-terraform'
                ]]) {
                    script {
                        // Capture monitoring IP from Terraform output
                        def monitoringIp = bat(
                            script: 'terraform output -raw monitoring_public_ip',
                            returnStdout: true
                        ).trim().readLines().last()

                        echo "Monitoring server IP: ${monitoringIp}"

                        // Wait up to 3 minutes for services to start (user_data takes time)
                        def maxRetries = 18
                        def retryDelay = 10
                        def prometheusReady = false
                        def grafanaReady    = false

                        for (int i = 1; i <= maxRetries; i++) {
                            echo "Health check attempt ${i}/${maxRetries}..."
                            try {
                                bat "curl -sf http://${monitoringIp}:9090/-/healthy > nul 2>&1"
                                prometheusReady = true
                            } catch (e) { /* not yet */ }

                            try {
                                bat "curl -sf http://${monitoringIp}:3000/api/health > nul 2>&1"
                                grafanaReady = true
                            } catch (e) { /* not yet */ }

                            if (prometheusReady && grafanaReady) break
                            if (i < maxRetries) sleep(retryDelay)
                        }

                        if (!prometheusReady) error("❌ Prometheus did not become healthy at http://${monitoringIp}:9090")
                        if (!grafanaReady)    error("❌ Grafana did not become healthy at http://${monitoringIp}:3000")

                        echo "✅ Prometheus healthy → http://${monitoringIp}:9090"
                        echo "✅ Grafana healthy    → http://${monitoringIp}:3000"
                        echo "✅ Alertmanager       → http://${monitoringIp}:9093"
                    }
                }
            }
        }
        // ── END Verify Monitoring Stack ───────────────────────────────────────

        stage('Manual Approval - Destroy (Optional)') {
            steps {
                timeout(time: 20, unit: 'MINUTES') {
                    input message: "Do you want to DESTROY all Terraform infrastructure?",
                          ok: "Destroy Now"
                }
            }
        }

        stage('Terraform Destroy') {
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'aws-terraform'
                ]]) {
                    bat 'terraform destroy -auto-approve'
                }
            }
        }
    }

    post {
        failure {
            echo '❌ Pipeline failed. Check Terraform logs.'
        }

        success {
            echo '✅ Terraform executed successfully!'
        }

        always {
            cleanWs()
        }
    }
}
