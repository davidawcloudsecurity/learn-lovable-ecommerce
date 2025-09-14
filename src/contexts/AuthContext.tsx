
import React, { createContext, useContext, useEffect, useState } from 'react';
import { cognitoAuth, CognitoUser, CognitoSession } from '@/lib/cognito';

interface AuthContextType {
  user: CognitoUser | null;
  session: CognitoSession | null;
  signUp: (email: string, password: string, firstName?: string, lastName?: string) => Promise<{ error: any }>;
  signIn: (email: string, password: string) => Promise<{ error: any }>;
  signOut: () => Promise<void>;
  loading: boolean;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export const useAuth = () => {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
};

export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [user, setUser] = useState<CognitoUser | null>(null);
  const [session, setSession] = useState<CognitoSession | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    // Check for existing session on mount
    const currentSession = cognitoAuth.getCurrentSession();
    if (currentSession && !cognitoAuth.isTokenExpired()) {
      setSession(currentSession);
      setUser(currentSession.user);
    }
    setLoading(false);

    // Poll for session changes (since Cognito doesn't have real-time auth state changes)
    const interval = setInterval(() => {
      const session = cognitoAuth.getCurrentSession();
      if (session && !cognitoAuth.isTokenExpired()) {
        setSession(session);
        setUser(session.user);
      } else if (session && cognitoAuth.isTokenExpired()) {
        // Token expired, clear session
        setSession(null);
        setUser(null);
        cognitoAuth.signOut();
      }
    }, 30000); // Check every 30 seconds

    return () => clearInterval(interval);
  }, []);

  const signUp = async (email: string, password: string, firstName?: string, lastName?: string) => {
    const result = await cognitoAuth.signUp(email, password, firstName, lastName);
    
    if (!result.success) {
      return { error: result.error };
    }
    
    // For Cognito, user needs to confirm their email
    // You might want to redirect to a confirmation page here
    return { error: null };
  };

  const signIn = async (email: string, password: string) => {
    const result = await cognitoAuth.signIn(email, password);
    
    if (!result.success) {
      return { error: result.error };
    }
    
    if (result.session) {
      setSession(result.session);
      setUser(result.session.user);
    }
    
    return { error: null };
  };

  const signOut = async () => {
    await cognitoAuth.signOut();
    setSession(null);
    setUser(null);
  };

  const value = {
    user,
    session,
    signUp,
    signIn,
    signOut,
    loading,
  };

  return (
    <AuthContext.Provider value={value}>
      {children}
    </AuthContext.Provider>
  );
};
