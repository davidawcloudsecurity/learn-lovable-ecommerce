
import React, { useState, useEffect, useCallback } from 'react';
import { ShoppingCart, Search, Globe, Menu, X, User, LogOut } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { useAuth } from '@/contexts/AuthContext';
import { useNavigate } from 'react-router-dom';
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";

const Header = () => {
  const [isMenuOpen, setIsMenuOpen] = useState(false);
  const [currency, setCurrency] = useState('USD');
  const [searchQuery, setSearchQuery] = useState('');
  const [suggestions, setSuggestions] = useState([]);
  const [showSuggestions, setShowSuggestions] = useState(false);
  const [profile, setProfile] = useState<any>(null);

  const { user, signOut, loading } = useAuth();
  const navigate = useNavigate();

  const currencies = ['USD', 'EUR', 'GBP', 'JPY', 'CNY'];

  // Fetch user profile data when user is available
  useEffect(() => {
    // Since we're using Cognito, user data is already available in the user object
    // No need to fetch from Supabase profiles table
    if (user) {
      setProfile({
        first_name: user.firstName,
        last_name: user.lastName
      });
    } else {
      setProfile(null);
    }
  }, [user]);

  // Debounce helper
  function debounce(func, wait) {
    let timeout;
    return function (...args) {
      clearTimeout(timeout);
      timeout = setTimeout(() => func(...args), wait);
    };
  }

  // Fetch suggestions with debounce
  const fetchSuggestions = useCallback(
    debounce(async (query) => {
      if (query.length < 2) {
        setSuggestions([]);
        return;
      }
      try {
        const res = await fetch(`/api/search/suggestions?q=${encodeURIComponent(query)}`);
        const data = await res.json();
        setSuggestions(data.suggestions || []);
        setShowSuggestions(true);
      } catch (err) {
        console.error('Suggestion error:', err);
      }
    }, 300),
    []
  );

  // On search input change
  const handleSearchChange = (e) => {
    const value = e.target.value;
    setSearchQuery(value);
    fetchSuggestions(value);
  };

  // Submit search
  const handleSearchSubmit = async (e) => {
    e.preventDefault();
    if (!searchQuery.trim()) return;

    setShowSuggestions(false);
    navigate(`/search?q=${encodeURIComponent(searchQuery)}`);
  };

  // Suggestion click
  const handleSuggestionClick = (s) => {
    setSearchQuery(s);
    setShowSuggestions(false);
    navigate(`/search?q=${encodeURIComponent(s)}`);
  };

  // Hide on outside click
  useEffect(() => {
    const hide = () => setShowSuggestions(false);
    document.addEventListener('click', hide);
    return () => document.removeEventListener('click', hide);
  }, []);

  const handleSignOut = async () => {
    await signOut();
    navigate('/');
  };

  return (
    <header className="bg-white shadow-md sticky top-0 z-50">
      <div className="container mx-auto px-4">
        <div className="flex items-center justify-between h-16">
          {/* Logo */}
          <div className="flex items-center space-x-2 cursor-pointer" onClick={() => navigate('/')}>
            <Globe className="h-8 w-8 text-blue-600" />
            <span className="text-2xl font-bold text-gray-900">GlobalTrade</span>
          </div>

          {/* Search Bar */}
          <div className="hidden md:flex flex-1 max-w-xl mx-8 relative">
            <form onSubmit={handleSearchSubmit} className="relative w-full">
              <input
                type="text"
                value={searchQuery}
                onChange={handleSearchChange}
                placeholder="Search products worldwide..."
                className="w-full px-4 py-2 pl-10 pr-4 border border-gray-300 rounded-full focus:outline-none focus:ring-2 focus:ring-blue-500"
                onClick={(e) => e.stopPropagation()}
              />
              <Search className="absolute left-3 top-2.5 h-5 w-5 text-gray-400" />
            </form>
            {/* Suggestions */}
            {showSuggestions && suggestions.length > 0 && (
              <div className="absolute top-full left-0 right-0 bg-white border border-gray-300 rounded-lg shadow-lg mt-1 z-50">
                {suggestions.map((s, i) => (
                  <div
                    key={i}
                    className="px-4 py-2 hover:bg-gray-100 cursor-pointer text-sm"
                    onClick={() => handleSuggestionClick(s)}
                  >
                    {s}
                  </div>
                ))}
              </div>
            )}
          </div>

          {/* Right Side */}
          <div className="flex items-center space-x-4">
            <select
              value={currency}
              onChange={(e) => setCurrency(e.target.value)}
              className="hidden sm:block border border-gray-300 rounded px-2 py-1 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
            >
              {currencies.map((curr) => (
                <option key={curr} value={curr}>
                  {curr}
                </option>
              ))}
            </select>

            <Button variant="outline" size="sm" className="relative">
              <ShoppingCart className="h-5 w-5" />
              <span className="absolute -top-2 -right-2 bg-red-500 text-white rounded-full text-xs w-5 h-5 flex items-center justify-center">
                3
              </span>
            </Button>

            {/* User Account */}
            {loading ? (
              <div className="w-8 h-8 rounded-full bg-gray-200 animate-pulse"></div>
            ) : user ? (
              <Popover>
                <PopoverTrigger asChild>
                  <Button variant="ghost" size="sm" className="flex items-center space-x-2">
                    <User className="h-5 w-5" />
                    <span className="hidden md:block">
                      {profile?.first_name || user.email?.split('@')[0]}
                    </span>
                  </Button>
                </PopoverTrigger>
                <PopoverContent className="w-48">
                  <div className="space-y-2">
                    <div className="px-2 py-1 text-sm text-gray-600">
                      {user.email}
                    </div>
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={handleSignOut}
                      className="w-full justify-start"
                    >
                      <LogOut className="h-4 w-4 mr-2" />
                      Sign Out
                    </Button>
                  </div>
                </PopoverContent>
              </Popover>
            ) : (
              <Button
                variant="default"
                size="sm"
                onClick={() => navigate('/auth')}
              >
                Sign In
              </Button>
            )}

            <Button
              variant="ghost"
              size="sm"
              className="md:hidden"
              onClick={() => setIsMenuOpen(!isMenuOpen)}
            >
              {isMenuOpen ? <X className="h-6 w-6" /> : <Menu className="h-6 w-6" />}
            </Button>
          </div>
        </div>

        {/* Mobile Menu */}
        {isMenuOpen && (
          <div className="md:hidden border-t border-gray-200 py-4">
            <form onSubmit={handleSearchSubmit} className="relative mb-4">
              <input
                type="text"
                value={searchQuery}
                onChange={handleSearchChange}
                placeholder="Search products..."
                className="w-full px-4 py-2 pl-10 border border-gray-300 rounded-full focus:outline-none focus:ring-2 focus:ring-blue-500"
                onClick={(e) => e.stopPropagation()}
              />
              <Search className="absolute left-3 top-2.5 h-5 w-5 text-gray-400" />
            </form>
            {showSuggestions && suggestions.length > 0 && (
              <div className="absolute z-50 bg-white w-full border border-gray-300 rounded-md shadow">
                {suggestions.map((s, i) => (
                  <div
                    key={i}
                    className="px-4 py-2 hover:bg-gray-100 cursor-pointer text-sm"
                    onClick={() => handleSuggestionClick(s)}
                  >
                    {s}
                  </div>
                ))}
              </div>
            )}
            <div className="space-y-2 mt-4">
              <a href="#" className="block py-2 text-gray-600 hover:text-blue-600">Electronics</a>
              <a href="#" className="block py-2 text-gray-600 hover:text-blue-600">Fashion</a>
              <a href="#" className="block py-2 text-gray-600 hover:text-blue-600">Home & Garden</a>
              <a href="#" className="block py-2 text-gray-600 hover:text-blue-600">Sports</a>
              {!user && (
                <Button
                  variant="default"
                  size="sm"
                  onClick={() => navigate('/auth')}
                  className="mt-4"
                >
                  Sign In
                </Button>
              )}
            </div>
          </div>
        )}
      </div>
    </header>
  );
};

export default Header;