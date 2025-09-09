pipeline {
  agent any

  environment {
    REPO_URL = 'https://github.com/SatyaAttili18/devops-project.git'
    IMAGE    = 'demo-app'
    TAG      = "build-${env.BUILD_NUMBER}"
  }

  options {
    timestamps()
  }

  stages {

    stage('Checkout') {
      steps {
        git branch: 'main', url: "${env.REPO_URL}"
      }
    }

    stage('Build Docker Image') {
      steps {
        sh '''
          echo "Building ${IMAGE}:${TAG}"
          docker build -t ${IMAGE}:${TAG} ./app
        '''
      }
    }

    stage('Smoke Test') {
      steps {
        sh '''
          CID=$(docker run -d -p 3999:3000 ${IMAGE}:${TAG})
          # small wait for app to boot
          sleep 3
          curl -fsS http://127.0.0.1:3999 >/dev/null
          docker rm -f "$CID"
        '''
      }
    }

    stage('Blue-Green Deploy') {
      steps {
        sh '''
          chmod +x scripts/deploy.sh scripts/rollback.sh || true
          # deploy to the non-live color; script flips Nginx on success
          scripts/deploy.sh ${IMAGE}:${TAG}
        '''
      }
    }
  }

  post {
    failure {
      echo 'Deploy failed — attempting traffic rollback (if needed)'
      sh 'scripts/rollback.sh || true'
    }
  }
}
