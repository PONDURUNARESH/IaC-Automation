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
