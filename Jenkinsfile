pipeline {
    agent any

    options {
        timestamps()
    }

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
                bat '''
                terraform --version
                terraform init -upgrade
                '''
            }
        }

        stage('Terraform Validate') {
            steps {
                bat 'terraform validate'
            }
        }

        stage('Terraform Plan') {
            steps {
                bat 'terraform plan -out=tfplan'
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

        stage('Archive PEM Key') {
            steps {
                archiveArtifacts artifacts: '*.pem', fingerprint: true
            }
        }
    }

    post {
        success {
            echo '✅ Infrastructure provisioned successfully!'
        }

        failure {
            echo '❌ Pipeline failed. Check Terraform logs.'
        }

        always {
            archiveArtifacts artifacts: '*.pem', fingerprint: true
            cleanWs()
        }
    }
}
