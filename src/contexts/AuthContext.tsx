import React, { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import { cognitoAuth, CognitoUser, CognitoSession } from '../lib/cognito';

interface AuthContextType {
  user: CognitoUser | null;
  session: CognitoSession | null;
  signUp: (email: string, password: string, firstName?: string, lastName?: string) => Promise<{ error: string | null }>;
  confirmSignUp: (email: string, code: string) => Promise<{ error: string | null }>;
  signIn: (email: string, password: string) => Promise<{ error: string | null }>;
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

interface AuthProviderProps {
  children: ReactNode;
}

export const AuthProvider: React.FC<AuthProviderProps> = ({ children }) => {
  const [user, setUser] = useState<CognitoUser | null>(null);
  const [session, setSession] = useState<CognitoSession | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const currentSession = cognitoAuth.getCurrentSession();
    if (currentSession && !cognitoAuth.isTokenExpired()) {
      setSession(currentSession);
      setUser(currentSession.user);
    }
    setLoading(false);
  }, []);

  const signUp = async (email: string, password: string, firstName?: string, lastName?: string) => {
    const result = await cognitoAuth.signUp(email, password, firstName, lastName);
    return result.success ? { error: null } : { error: result.error };
  };

  const confirmSignUp = async (email: string, code: string) => {
    const result = await cognitoAuth.confirmSignUp(email, code);
    return result.success ? { error: null } : { error: result.error };
  };

  const signIn = async (email: string, password: string) => {
    const result = await cognitoAuth.signIn(email, password);
    if (result.success && result.session) {
      setSession(result.session);
      setUser(result.session.user);
      return { error: null };
    }
    return { error: result.error };
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
    confirmSignUp,
    signIn,
    signOut,
    loading,
  };

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
};
