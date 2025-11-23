pipeline {
    agent any

    environment {
        AWS_ACCESS_KEY_ID     = credentials('aws-creds').USR
        AWS_SECRET_ACCESS_KEY = credentials('aws-creds').PSW
        AWS_DEFAULT_REGION    = "ap-south-1"  // change if needed
    }

    stages {
        stage('Checkout Code') {
            steps {
                git branch: 'main', url: 'https://github.com/PONDURUNARESH/IaC-Automation.git'
            }
        }

        stage('Terraform Init') {
            steps {
                sh 'terraform init'
            }
        }

        stage('Terraform Validate') {
            steps {
                sh 'terraform validate'
            }
        }

        stage('Terraform Plan') {
            steps {
                sh 'terraform plan -out=tfplan'
            }
        }

        stage('Terraform Apply') {
            when {
                branch 'main'
            }
            steps {
                sh 'terraform apply -auto-approve tfplan'
            }
        }
    }

    post {
        success {
            echo "Terraform deployment completed successfully!"
        }
        failure {
            echo "Terraform pipeline failed. Check logs."
        }
    }
}
