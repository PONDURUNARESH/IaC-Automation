pipeline {
    agent any

    options {
        timestamps()
    }

    triggers {
        // Poll GitHub every 1 minute to detect new commits
        pollSCM('*/1 * * * *')
    }

    stages {

        stage('Checkout') {
            steps {
                git branch: 'main', url: 'https://github.com/PONDURUNARESH/IaC-Automation.git'
            }
        }

        stage('Terraform Init') {
            steps {
                bat """
                terraform --version
                terraform init -upgrade
                """
            }
        }

        stage('Terraform Validate') {
            steps {
                bat "terraform validate"
            }
        }

        stage('Terraform Plan') {
            steps {
                bat "terraform plan -out=tfplan"
            }
        }

        stage('Terraform Apply (Auto)') {
            steps {
                echo "Auto-applying Terraform changes..."
                bat "terraform apply -auto-approve tfplan"
            }
        }

        stage('Approval for DESTROY (1 hour)') {
            when {
                branch 'main'
            }
            steps {
                timeout(time: 1, unit: 'HOURS') {
                    input message: "Do you want to DESTROY all Terraform resources?", ok: "Yes, Destroy"
                }
            }
        }

        stage('Terraform Destroy') {
            when {
                branch 'main'
            }
            steps {
                bat "terraform destroy -auto-approve"
            }
        }
    }

    post {
        always {
            cleanWs()
        }
    }
}