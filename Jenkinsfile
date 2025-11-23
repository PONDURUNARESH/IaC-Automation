pipeline {
  agent any

  environment {
    AWS_DEFAULT_REGION = "ap-south-1"
  }

  options {
    buildDiscarder(logRotator(numToKeepStr: '20'))
    timestamps()
  }

  stages {

    stage('Checkout') {
      steps {
        // Simple checkout for public GitHub repo
        checkout([$class: 'GitSCM',
          branches: [[name: '*/main']],
          userRemoteConfigs: [[url: 'https://github.com/PONDURUNARESH/IaC-Automation.git']]
        ])
      }
    }

    stage('Prepare') {
      steps {
        bat 'terraform --version'
        bat 'git --version'
      }
    }

    stage('Terraform Init') {
      steps {
        bat 'terraform init -input=false'
      }
    }

    stage('Terraform Validate') {
      steps {
        bat 'terraform validate'
      }
    }

    stage('Terraform Plan') {
      steps {
        bat 'terraform plan -out=tfplan -input=false'
        bat 'terraform show -no-color tfplan > plan.txt'
        archiveArtifacts artifacts: 'plan.txt', fingerprint: true
      }
    }

    stage('Terraform Apply (Auto)') {
      when {
        branch 'main'
      }
      steps {
        bat 'terraform apply -input=false -auto-approve tfplan'
      }
    }
  }

  post {
    success {
      echo "Pipeline completed successfully!"
    }
    failure {
      echo "Pipeline failed. Check console logs."
    }
  }
}
