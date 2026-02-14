#!/bin/bash
set -e

ENVIRONMENT=${1:-dev}
DESTROY=${2:-false}
PROJECT_NAME="twin"
BACKEND_BUCKET="${PROJECT_NAME}-terraform-state-${AWS_ACCOUNT_ID}"
BACKEND_KEY="${PROJECT_NAME}/${ENVIRONMENT}/terraform.tfstate"

echo "🚀 Deploying twin to $ENVIRONMENT..."

# Build Lambda package
echo "📦 Building Lambda package..."
cd backend

# Install uv for faster dependency management
python3 -m pip install --upgrade pip uv

# Create virtual environment and install dependencies
uv venv
source .venv/bin/activate || . .venv/bin/activate
uv pip install -r requirements.txt

# Create package directory
rm -rf package
mkdir -p package

# Install dependencies for Lambda using Docker
echo "Installing dependencies for Lambda runtime..."
docker run --rm \
  -v "$PWD":/var/task \
  --entrypoint /bin/bash \
  public.ecr.aws/lambda/python:3.12 \
  -c "pip install -r /var/task/requirements.txt -t /var/task/package/"

# Copy application files to package
echo "Copying application files..."
cp *.py package/ 2>/dev/null || true
cp -r data package/ 2>/dev/null || true
cp *.txt package/ 2>/dev/null || true

# Create zip file
echo "Creating zip file..."
cd package
zip -r ../lambda-deployment.zip . -q
cd ..

SIZE=$(du -h lambda-deployment.zip | cut -f1)
echo "✓ Created lambda-deployment.zip ($SIZE)"

cd ..

# Check and create Terraform backend if needed
echo "🔧 Setting up Terraform backend..."
if [ -d "terraform-backend" ]; then
  echo "📦 Creating S3 backend bucket and DynamoDB table..."
  cd terraform-backend
  terraform init
  terraform apply -auto-approve \
    -var="region=${DEFAULT_AWS_REGION}" \
    -var="project_name=${PROJECT_NAME}"
  cd ..
  echo "✓ Backend resources created"
else
  echo "⚠️  terraform-backend directory not found, assuming backend already exists"
fi

# Initialize Terraform with S3 backend
echo "🔄 Initializing Terraform with S3 backend..."
cd terraform
terraform init -reconfigure \
  -backend-config="bucket=${BACKEND_BUCKET}" \
  -backend-config="key=${BACKEND_KEY}" \
  -backend-config="region=${DEFAULT_AWS_REGION}" \
  -backend-config="encrypt=true"

# Select or create workspace
echo "🔀 Setting up workspace: $ENVIRONMENT"
terraform workspace select $ENVIRONMENT 2>/dev/null || terraform workspace new $ENVIRONMENT

# Destroy existing resources if requested
if [ "$DESTROY" = "true" ]; then
  echo "🗑️  Destroying existing infrastructure..."
  terraform destroy -var-file=terraform.tfvars -auto-approve || true
  echo "✓ Existing resources destroyed"
fi

# Deploy infrastructure
echo "☁️ Deploying infrastructure to $ENVIRONMENT..."
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars -auto-approve

# Get outputs
echo "📋 Deployment outputs:"
terraform output

# Deploy frontend
echo "🌐 Deploying frontend..."
cd ../frontend

# Build Next.js app
npm install
npm run build

# Get S3 bucket name from Terraform output
S3_BUCKET=$(cd ../terraform && terraform output -raw frontend_bucket_name)

# Sync to S3
echo "📤 Uploading frontend to S3 bucket: $S3_BUCKET"
aws s3 sync out/ s3://$S3_BUCKET/ --delete

# Invalidate CloudFront cache
CLOUDFRONT_ID=$(cd ../terraform && terraform output -raw cloudfront_distribution_id)
echo "🔄 Invalidating CloudFront cache: $CLOUDFRONT_ID"
aws cloudfront create-invalidation --distribution-id $CLOUDFRONT_ID --paths "/*"

cd ..

echo "✅ Deployment complete!"
echo ""
echo "🔗 Frontend URL: $(cd terraform && terraform output -raw cloudfront_url)"
echo "🔗 API URL: $(cd terraform && terraform output -raw api_url)"
