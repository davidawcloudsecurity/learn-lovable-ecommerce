import {
  CognitoIdentityProviderClient,
  SignUpCommand,
  ConfirmSignUpCommand,
  InitiateAuthCommand,
  AuthFlowType,
  GetUserCommand,
  GlobalSignOutCommand,
} from '@aws-sdk/client-cognito-identity-provider';

// AWS Cognito configuration - Update these values with your actual Cognito settings
const REGION = process.env.VITE_AWS_REGION || 'us-east-1';
const USER_POOL_ID = process.env.VITE_COGNITO_USER_POOL_ID || 'us-east-1_ty2PwS9N2'; // e.g., 'us-east-1_xxxxxxxxx'
const CLIENT_ID = process.env.VITE_COGNITO_CLIENT_ID || '32bj378nkok3url0s8v9nu7sve'; // Your App Client ID

// Validate configuration
if (!USER_POOL_ID || !CLIENT_ID) {
  console.error('AWS Cognito configuration missing. Please set VITE_COGNITO_USER_POOL_ID and VITE_COGNITO_CLIENT_ID environment variables.');
}

const cognitoClient = new CognitoIdentityProviderClient({
  region: REGION,
});

export interface CognitoUser {
  username: string;
  email: string;
  firstName?: string;
  lastName?: string;
  emailVerified: boolean;
}

export interface CognitoSession {
  accessToken: string;
  idToken: string;
  refreshToken: string;
  user: CognitoUser;
}

class CognitoAuthService {
  private session: CognitoSession | null = null;

  constructor() {
    // Load session from localStorage on initialization
    this.loadSessionFromStorage();
  }

  private saveSessionToStorage(session: CognitoSession | null) {
    if (session) {
      localStorage.setItem('cognito_session', JSON.stringify(session));
    } else {
      localStorage.removeItem('cognito_session');
    }
    this.session = session;
  }

  private loadSessionFromStorage() {
    try {
      const stored = localStorage.getItem('cognito_session');
      if (stored) {
        this.session = JSON.parse(stored);
      }
    } catch (error) {
      console.error('Error loading session from storage:', error);
      localStorage.removeItem('cognito_session');
    }
  }

  async signUp(email: string, password: string, firstName?: string, lastName?: string) {
    try {
      const attributes = [
        { Name: 'email', Value: email },
      ];

      if (firstName) {
        attributes.push({ Name: 'given_name', Value: firstName });
      }

      if (lastName) {
        attributes.push({ Name: 'family_name', Value: lastName });
      }

      const command = new SignUpCommand({
        ClientId: CLIENT_ID,
        Username: email,
        Password: password,
        UserAttributes: attributes,
      });

      const response = await cognitoClient.send(command);
      
      return {
        success: true,
        userSub: response.UserSub,
        codeDeliveryDetails: response.CodeDeliveryDetails,
      };
    } catch (error: any) {
      return {
        success: false,
        error: error.message || 'Sign up failed',
      };
    }
  }

  async confirmSignUp(email: string, confirmationCode: string) {
    try {
      const command = new ConfirmSignUpCommand({
        ClientId: CLIENT_ID,
        Username: email,
        ConfirmationCode: confirmationCode,
      });

      await cognitoClient.send(command);
      
      return { success: true };
    } catch (error: any) {
      return {
        success: false,
        error: error.message || 'Confirmation failed',
      };
    }
  }

  async signIn(email: string, password: string) {
    try {
      const command = new InitiateAuthCommand({
        ClientId: CLIENT_ID,
        AuthFlow: AuthFlowType.USER_PASSWORD_AUTH,
        AuthParameters: {
          USERNAME: email,
          PASSWORD: password,
        },
      });

      const response = await cognitoClient.send(command);

      if (response.AuthenticationResult) {
        const { AccessToken, IdToken, RefreshToken } = response.AuthenticationResult;
        
        if (AccessToken && IdToken && RefreshToken) {
          // Get user details
          const user = await this.getUserFromToken(AccessToken);
          
          const session: CognitoSession = {
            accessToken: AccessToken,
            idToken: IdToken,
            refreshToken: RefreshToken,
            user,
          };

          this.saveSessionToStorage(session);
          
          return { success: true, session };
        }
      }

      return {
        success: false,
        error: 'Invalid authentication response',
      };
    } catch (error: any) {
      return {
        success: false,
        error: error.message || 'Sign in failed',
      };
    }
  }

  async signOut() {
    try {
      if (this.session?.accessToken) {
        const command = new GlobalSignOutCommand({
          AccessToken: this.session.accessToken,
        });

        await cognitoClient.send(command);
      }
    } catch (error) {
      console.error('Error signing out from Cognito:', error);
    } finally {
      this.saveSessionToStorage(null);
    }
  }

  private async getUserFromToken(accessToken: string): Promise<CognitoUser> {
    try {
      const command = new GetUserCommand({
        AccessToken: accessToken,
      });

      const response = await cognitoClient.send(command);
      
      const email = response.UserAttributes?.find(attr => attr.Name === 'email')?.Value || '';
      const firstName = response.UserAttributes?.find(attr => attr.Name === 'given_name')?.Value;
      const lastName = response.UserAttributes?.find(attr => attr.Name === 'family_name')?.Value;
      const emailVerified = response.UserAttributes?.find(attr => attr.Name === 'email_verified')?.Value === 'true';

      return {
        username: response.Username || '',
        email,
        firstName,
        lastName,
        emailVerified,
      };
    } catch (error) {
      throw new Error('Failed to get user information');
    }
  }

  getCurrentSession(): CognitoSession | null {
    return this.session;
  }

  getCurrentUser(): CognitoUser | null {
    return this.session?.user || null;
  }

  // Check if token is expired (basic check)
  isTokenExpired(): boolean {
    if (!this.session?.idToken) return true;
    
    try {
      const payload = JSON.parse(atob(this.session.idToken.split('.')[1]));
      const currentTime = Math.floor(Date.now() / 1000);
      return payload.exp < currentTime;
    } catch {
      return true;
    }
  }

  // Refresh token logic would go here
  async refreshSession(): Promise<boolean> {
    // Implementation for token refresh using RefreshToken
    // This would use the RefreshTokenAuthFlow
    return false;
  }
}

export const cognitoAuth = new CognitoAuthService();
