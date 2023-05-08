# Initializing Terraform Backend in AWS (S3 and DynamoDB)

> Sources:
> - [deploy a terraform remote state backend with cloudformation](https://mikevanbuskirk.io/posts/terraform-backend-with-cloudformation/)

```bash
aws cloudformation create-stack --stack-name terraform-backend --template-body file://tf-backend-setup.cfn --parameters ParameterKey=StateBucketName,ParameterValue=<your_bucket_name> ParameterKey=LockTableName,ParameterValue=<your_lock_table_name>
```

Add `--profile XYZ` if necessary

