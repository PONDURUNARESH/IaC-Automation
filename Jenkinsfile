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

        stage('Archive PEM Key') {
            steps {
                archiveArtifacts artifacts: '*.pem', fingerprint: true
            }
        }

        // ── Verify Monitoring Stack ───────────────────────────────────────────
        // user_data installs Prometheus + Grafana which takes 8-12 min on a
        // fresh Amazon Linux 2 instance (yum update + binary downloads).
        // We poll for up to 15 minutes (90 attempts x 10s).
        stage('Verify Monitoring Stack') {
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'aws-terraform'
                ]]) {
                    script {
                        def monitoringIp = bat(
                            script: 'terraform output -raw monitoring_public_ip',
                            returnStdout: true
                        ).trim().readLines().last()

                        echo "Monitoring server IP: ${monitoringIp}"
                        echo "Waiting up to 15 minutes for Prometheus and Grafana to start..."

                        def maxRetries  = 90   // 90 x 10s = 15 minutes
                        def retryDelay  = 10
                        def prometheusOk = false
                        def grafanaOk    = false

                        for (int i = 1; i <= maxRetries; i++) {
                            echo "Health check ${i}/${maxRetries} — elapsed ~${(i-1)*retryDelay}s"

                            if (!prometheusOk) {
                                def rc = bat(
                                    script: "curl -sf --connect-timeout 5 http://${monitoringIp}:9090/-/healthy > nul 2>&1",
                                    returnStatus: true
                                )
                                prometheusOk = (rc == 0)
                                if (prometheusOk) echo "✅ Prometheus is UP"
                            }

                            if (!grafanaOk) {
                                def rc = bat(
                                    script: "curl -sf --connect-timeout 5 http://${monitoringIp}:3000/api/health > nul 2>&1",
                                    returnStatus: true
                                )
                                grafanaOk = (rc == 0)
                                if (grafanaOk) echo "✅ Grafana is UP"
                            }

                            if (prometheusOk && grafanaOk) {
                                echo "✅ All monitoring services are healthy!"
                                echo "   Prometheus   → http://${monitoringIp}:9090"
                                echo "   Grafana      → http://${monitoringIp}:3000"
                                echo "   Alertmanager → http://${monitoringIp}:9093"
                                break
                            }

                            if (i < maxRetries) sleep(retryDelay)
                        }

                        if (!prometheusOk) error("❌ Prometheus did not become healthy at http://${monitoringIp}:9090 within 15 minutes.\nSSH in and check: cat /var/log/monitoring-install.log")
                        if (!grafanaOk)    error("❌ Grafana did not become healthy at http://${monitoringIp}:3000 within 15 minutes.\nSSH in and check: sudo journalctl -u grafana-server -n 50")
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