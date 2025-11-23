pipeline {
  agent any

  environment {
    AWS_DEFAULT_REGION = "ap-south-1"   // change as needed
  }

  options {
    ansiColor('xterm')
    buildDiscarder(logRotator(numToKeepStr: '20'))
    timestamps()
  }

  stages {
    stage('Checkout') {
      steps {
        // lightweight checkout used if configured in job
        checkout([$class: 'GitSCM', branches: [[name: '*/main']],
          userRemoteConfigs: [[url: 'https://github.com/PONDURUNARESH/IaC-Automation.git', credentialsId: 'github-token']]] )
      }
    }

    stage('Prepare') {
      steps {
        // print versions for troubleshooting
        sh 'terraform --version || true'
        sh 'git --version || true'
      }
    }

    stage('Terraform Init') {
      steps {
        // ensures init runs and creates plugins
        sh 'terraform init -input=false'
      }
    }

    stage('Terraform Validate') {
      steps {
        sh 'terraform validate'
      }
    }

    stage('Terraform Plan') {
      steps {
        // create a binary plan + a human-readable plan for review
        sh 'terraform plan -out=tfplan -input=false'
        sh 'terraform show -no-color tfplan > plan.txt || true'
        archiveArtifacts artifacts: 'plan.txt', fingerprint: true
      }
    }

    stage('Terraform Apply (auto)') {
      when {
        branch 'main'
      }
      steps {
        sh 'terraform apply -input=false -auto-approve tfplan'
      }
    }
  }

  post {
    success {
      echo "Pipeline successful"
    }
    failure {
      echo "Pipeline failed: check console output"
    }
  }
}
