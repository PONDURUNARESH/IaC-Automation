pipeline {
    agent any

    environment {
        // Inject AWS credentials from Jenkins Credential ID = 'aws-cred'
        AWS_ACCESS_KEY_ID     = credentials('aws-cred')
        AWS_SECRET_ACCESS_KEY = credentials('aws-cred')
    }

    options {
        timestamps()
    }

    triggers {
        // Poll GitHub every 2 minutes
        pollSCM('H/2 * * * *')
    }

    stages {

        stage('Checkout') {
            steps {
                git branch: 'main', url: 'https://github.com/PONDURUNARESH/IaC-Automation.git'
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
                    input message: "Do you want to APPLY the Terraform changes?", ok: "Yes, Apply"
                }
            }
        }

        stage('Terraform Apply') {
            steps {
                bat 'terraform apply -auto-approve tfplan'
            }
        }

        stage('Manual Approval - Destroy (Optional)') {
            steps {
                timeout(time: 20, unit: 'MINUTES') {
                    input message: "Do you want to DESTROY all Terraform infrastructure?", ok: "Destroy Now"
                }
            }
        }

        stage('Terraform Destroy') {
            steps {
                bat 'terraform destroy -auto-approve'
            }
        }
    }

    post {
        always {
            cleanWs()
        }
    }
}
