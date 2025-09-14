# AWS Cognito Setup Guide

This application has been migrated from Supabase to AWS Cognito for authentication. Follow these steps to configure Cognito.

## Prerequisites

1. AWS Account
2. AWS CLI configured (optional but recommended)

## Step 1: Create a Cognito User Pool

1. Go to the AWS Console and navigate to Amazon Cognito
2. Click "Create user pool"
3. Configure the following settings:

### Step 1: Configure sign-in experience
- **Cognito user pool sign-in options**: Email
- **User pool sign-in options**: Email

### Step 2: Configure security requirements
- **Password policy**: Choose according to your requirements
- **Multi-factor authentication**: Optional (recommended: Optional MFA)
- **User account recovery**: Email only

### Step 3: Configure sign-up experience
- **Self-service sign-up**: Enable
- **Cognito-assisted verification and confirmation**: 
  - Email: Send email, verify email address
- **Required attributes**: Email
- **Optional attributes**: Given name, Family name

### Step 4: Configure message delivery
- **Email**: Send email with Cognito
  - Or configure with Amazon SES for production

### Step 5: Integrate your app
- **User pool name**: Choose a name (e.g., "GlobalTrade-UserPool")
- **App client name**: Choose a name (e.g., "GlobalTrade-WebClient")
- **Client secret**: Don't generate a client secret (for web apps)

### Step 6: Review and create
- Review all settings and create the user pool

## Step 2: Configure Environment Variables

After creating the User Pool, you'll need to add these environment variables to your project:

1. **User Pool ID**: Found in the User Pool overview page
2. **App Client ID**: Found in the App clients tab of your User Pool

Create/update your `.env` file:

```env
VITE_AWS_REGION=us-east-1
VITE_COGNITO_USER_POOL_ID=us-east-1_xxxxxxxxx
VITE_COGNITO_CLIENT_ID=your-client-id-here
```

## Step 3: Configure App Client Settings

1. In your User Pool, go to "App clients" tab
2. Click on your app client
3. Configure the following:

### Authentication flows
- [x] ALLOW_USER_PASSWORD_AUTH
- [x] ALLOW_REFRESH_TOKEN_AUTH

### App client settings (if using Hosted UI)
- **Callback URLs**: Add your application URLs (e.g., `http://localhost:5173`, your production URL)
- **Sign out URLs**: Add your application URLs
- **OAuth 2.0 settings**: 
  - Allowed OAuth Flows: Authorization code grant
  - Allowed OAuth Scopes: email, openid, profile

## Step 4: Update Application Settings

The application is already configured to use Cognito. Make sure:

1. Environment variables are set correctly
2. AWS credentials are configured (if needed for advanced features)
3. The application has the necessary permissions

## Important Notes

### Email Confirmation
- New users will need to confirm their email address before they can sign in
- Check the email confirmation flow in your application
- Consider disabling email confirmation for development/testing

### Token Management
- Access tokens expire after 1 hour by default
- Refresh tokens can be used to get new access tokens
- The application handles basic token management and persistence

### Security Considerations
- User Pool configuration affects security
- Consider enabling MFA for production
- Review password policies
- Set up proper monitoring and logging

## Migration from Supabase

If you're migrating from Supabase:

1. Export user data from Supabase (if needed)
2. Users will need to re-register with Cognito
3. Update any user-specific data storage to use Cognito user IDs
4. Remove Supabase authentication dependencies

## Troubleshooting

### Common Issues:

1. **Configuration missing errors**: Make sure environment variables are set
2. **Authentication flows not enabled**: Check App Client settings
3. **Email delivery issues**: Configure SES or check Cognito email limits
4. **Token expiration issues**: Implement proper token refresh logic

### Debug Mode:
The application logs authentication events to the console. Check browser developer tools for detailed error messages.