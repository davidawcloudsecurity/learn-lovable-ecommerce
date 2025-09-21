import React, { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Separator } from '@/components/ui/separator';
import { useToast } from '@/hooks/use-toast';
import { 
  ArrowLeft, 
  ShoppingCart, 
  Package, 
  Star,
  Heart,
  Share2
} from 'lucide-react';

const S3_BUCKET_URL = '';
const S3_IMAGES_PATH = '/assets/images/';

interface Product {
  id: number;
  name: string;
  price: number;
  originalPrice?: number;
  image: string;
  country: string;
  flag: string;
  rating: number;
  reviews: number;
  shipping: string;
  category: string;
  description?: string;
}

const ProductDetail = () => {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { toast } = useToast();
  const [product, setProduct] = useState<Product | null>(null);
  const [loading, setLoading] = useState(true);
  const [quantity, setQuantity] = useState(1);

  // Mock product data - in a real app, this would come from an API
  const mockProducts: Product[] = [
    {
      id: 1,
      name: 'MacBook Pro',
      price: 2500,
      originalPrice: 2800,
      image: 'photo-1647805256812-ccb927cf1f67',
      country: 'USA',
      flag: '🇺🇸',
      rating: 4.8,
      reviews: 1250,
      shipping: 'Free shipping',
      category: 'Electronics',
      description: 'The MacBook Pro is a line of Macintosh portable computers introduced in January 2006 by Apple Inc. It is the higher-end model of the MacBook family, sitting above the consumer-focused MacBook Air.'
    },
    {
      id: 2,
      name: 'Lamp Shade',
      price: 25,
      originalPrice: 35,
      image: 'photo-1694353560850-436cb191fb8c',
      country: 'Italy',
      flag: '🇮🇹',
      rating: 4.2,
      reviews: 89,
      shipping: '$5.99 shipping',
      category: 'Home & Garden',
      description: 'Beautiful handcrafted lamp shade made from premium materials. Perfect for adding warmth and style to any room.'
    },
    {
      id: 3,
      name: 'Laser Printer',
      price: 150,
      originalPrice: 199,
      image: 'photo-1625961332771-3f40b0e2bdcf',
      country: 'Japan',
      flag: '🇯🇵',
      rating: 4.5,
      reviews: 456,
      shipping: 'Free shipping',
      category: 'Electronics',
      description: 'High-quality laser printer with fast printing speeds and crisp text quality. Perfect for home or office use.'
    },
    {
      id: 4,
      name: 'Laptop Stand',
      price: 45,
      originalPrice: 60,
      image: 'photo-1623251606108-512c7c4a3507',
      country: 'Germany',
      flag: '🇩🇪',
      rating: 4.3,
      reviews: 234,
      shipping: '$3.99 shipping',
      category: 'Electronics',
      description: 'Ergonomic laptop stand designed to improve posture and reduce neck strain. Adjustable height and angle.'
    },
    {
      id: 5,
      name: 'LED Light Bulb',
      price: 12,
      originalPrice: 18,
      image: 'photo-1553213134-f60afad82ceb',
      country: 'China',
      flag: '🇨🇳',
      rating: 4.1,
      reviews: 567,
      shipping: 'Free shipping',
      category: 'Home & Garden',
      description: 'Energy-efficient LED light bulb with long lifespan. Available in warm and cool white options.'
    },
    {
      id: 6,
      name: 'Luggage Set',
      price: 120,
      originalPrice: 160,
      image: 'photo-1708403120467-1715bb6840df',
      country: 'France',
      flag: '🇫🇷',
      rating: 4.6,
      reviews: 123,
      shipping: '$8.99 shipping',
      category: 'Travel',
      description: 'Premium luggage set with durable construction and smooth-rolling wheels. Perfect for business or leisure travel.'
    },
    {
      id: 7,
      name: 'Camping Lantern',
      price: 35,
      originalPrice: 50,
      image: 'photo-1570739260082-39a84dae80c8',
      country: 'Canada',
      flag: '🇨🇦',
      rating: 4.4,
      reviews: 198,
      shipping: 'Free shipping',
      category: 'Outdoor',
      description: 'Portable camping lantern with multiple brightness settings and long battery life. Weather-resistant design.'
    }
  ];

  useEffect(() => {
    // Simulate API call
    const fetchProduct = async () => {
      setLoading(true);
      // In a real app, you'd fetch from your API: /api/products/${id}
      const foundProduct = mockProducts.find(p => p.id === parseInt(id || '0'));
      
      // Simulate network delay
      await new Promise(resolve => setTimeout(resolve, 500));
      
      setProduct(foundProduct || null);
      setLoading(false);
    };

    if (id) {
      fetchProduct();
    }
  }, [id]);

  const handleAddToCart = () => {
    if (!product) return;

    // Navigate to checkout with product data
    const params = new URLSearchParams({
      productId: product.id.toString(),
      productName: product.name,
      productPrice: product.price.toString(),
      productImage: product.image,
      productCountry: product.country,
      productFlag: product.flag,
      productRating: product.rating.toString(),
      productReviews: product.reviews.toString(),
      productShipping: product.shipping,
      quantity: quantity.toString(),
      ...(product.originalPrice && { originalPrice: product.originalPrice.toString() })
    });
    
    navigate(`/checkout?${params.toString()}`);
  };

  const handleShare = () => {
    if (navigator.share) {
      navigator.share({
        title: product?.name,
        text: `Check out this ${product?.name} for $${product?.price}`,
        url: window.location.href,
      });
    } else {
      // Fallback: copy to clipboard
      navigator.clipboard.writeText(window.location.href);
      toast({
        title: "Link copied!",
        description: "Product link has been copied to clipboard.",
      });
    }
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-background">
        <div className="container mx-auto px-4 py-8">
          <div className="animate-pulse">
            <div className="h-8 bg-gray-200 rounded w-1/4 mb-8"></div>
            <div className="grid lg:grid-cols-2 gap-8">
              <div className="h-96 bg-gray-200 rounded"></div>
              <div className="space-y-4">
                <div className="h-8 bg-gray-200 rounded w-3/4"></div>
                <div className="h-4 bg-gray-200 rounded w-1/2"></div>
                <div className="h-6 bg-gray-200 rounded w-1/4"></div>
                <div className="h-20 bg-gray-200 rounded"></div>
              </div>
            </div>
          </div>
        </div>
      </div>
    );
  }

  if (!product) {
    return (
      <div className="min-h-screen bg-background">
        <div className="container mx-auto px-4 py-8">
          <div className="text-center">
            <h1 className="text-2xl font-bold mb-4">Product Not Found</h1>
            <p className="text-muted-foreground mb-8">The product you're looking for doesn't exist.</p>
            <Button onClick={() => navigate('/')}>
              <ArrowLeft className="h-4 w-4 mr-2" />
              Back to Home
            </Button>
          </div>
        </div>
      </div>
    );
  }

  const discountPercentage = product.originalPrice 
    ? Math.round(((product.originalPrice - product.price) / product.originalPrice) * 100)
    : 0;

  return (
    <div className="min-h-screen bg-background">
      <div className="container mx-auto px-4 py-8 max-w-6xl">
        {/* Back Button */}
        <div className="flex items-center gap-4 mb-8">
          <Button
            variant="ghost"
            size="icon"
            onClick={() => navigate(-1)}
            className="rounded-full"
          >
            <ArrowLeft className="h-4 w-4" />
          </Button>
          <div className="text-sm text-muted-foreground">
            <span className="hover:text-foreground cursor-pointer" onClick={() => navigate('/')}>
              Home
            </span>
            <span className="mx-2">/</span>
            <span className="hover:text-foreground cursor-pointer">
              {product.category}
            </span>
            <span className="mx-2">/</span>
            <span>{product.name}</span>
          </div>
        </div>

        {/* Product Details */}
        <div className="grid lg:grid-cols-2 gap-12">
          {/* Product Image */}
          <div className="space-y-4">
            <div className="relative overflow-hidden rounded-lg border">
              <img
                src={`${S3_BUCKET_URL}${S3_IMAGES_PATH}${product.image}`}
                alt={product.name}
                className="w-full h-96 object-cover"
              />
              {discountPercentage > 0 && (
                <div className="absolute top-4 left-4 bg-red-500 text-white px-2 py-1 rounded text-sm font-bold">
                  -{discountPercentage}% OFF
                </div>
              )}
              <div className="absolute top-4 right-4 flex items-center bg-white/90 backdrop-blur-sm rounded-full px-3 py-1">
                <span className="text-lg mr-2">{product.flag}</span>
                <span className="text-sm font-medium text-gray-600">{product.country}</span>
              </div>
            </div>
          </div>

          {/* Product Info */}
          <div className="space-y-6">
            <div>
              <div className="inline-block bg-secondary text-secondary-foreground px-2 py-1 rounded text-sm font-medium mb-2">
                {product.category}
              </div>
              <h1 className="text-3xl font-bold text-foreground mb-2">
                {product.name}
              </h1>
              
              {/* Rating */}
              <div className="flex items-center gap-2 mb-4">
                <div className="flex items-center">
                  {[...Array(5)].map((_, i) => (
                    <Star
                      key={i}
                      className={`h-4 w-4 ${
                        i < Math.floor(product.rating)
                          ? 'fill-yellow-400 text-yellow-400'
                          : 'text-gray-300'
                      }`}
                    />
                  ))}
                </div>
                <span className="text-sm font-medium">{product.rating}</span>
                <span className="text-sm text-muted-foreground">
                  ({product.reviews} reviews)
                </span>
              </div>
            </div>

            {/* Price */}
            <div className="space-y-2">
              <div className="flex items-center gap-3">
                <span className="text-3xl font-bold text-blue-600">
                  ${product.price}
                </span>
                {product.originalPrice && (
                  <span className="text-xl text-muted-foreground line-through">
                    ${product.originalPrice}
                  </span>
                )}
              </div>
              
              {/* Shipping */}
              <div className="flex items-center text-sm text-muted-foreground">
                <Package className="h-4 w-4 mr-2" />
                <span>{product.shipping}</span>
              </div>
            </div>

            <Separator />

            {/* Description */}
            <div>
              <h3 className="font-semibold mb-2">Description</h3>
              <p className="text-muted-foreground leading-relaxed">
                {product.description}
              </p>
            </div>

            <Separator />

            {/* Quantity and Actions */}
            <div className="space-y-4">
              <div className="flex items-center gap-4">
                <label className="font-medium">Quantity:</label>
                <div className="flex items-center border rounded-md">
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => setQuantity(Math.max(1, quantity - 1))}
                    disabled={quantity <= 1}
                  >
                    -
                  </Button>
                  <span className="px-4 py-2 min-w-[3rem] text-center">{quantity}</span>
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => setQuantity(quantity + 1)}
                  >
                    +
                  </Button>
                </div>
              </div>

              <div className="flex gap-3">
                <Button
                  onClick={handleAddToCart}
                  className="flex-1 bg-blue-600 hover:bg-blue-700"
                  size="lg"
                >
                  <ShoppingCart className="h-4 w-4 mr-2" />
                  Add to Cart
                </Button>
                <Button
                  variant="outline"
                  size="lg"
                  onClick={handleShare}
                >
                  <Share2 className="h-4 w-4" />
                </Button>
                <Button
                  variant="outline"
                  size="lg"
                >
                  <Heart className="h-4 w-4" />
                </Button>
              </div>
            </div>

            {/* Additional Info */}
            <Card>
              <CardContent className="pt-6">
                <div className="space-y-3 text-sm">
                  <div className="flex justify-between">
                    <span className="text-muted-foreground">SKU:</span>
                    <span>PROD-{product.id.toString().padStart(6, '0')}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-muted-foreground">Category:</span>
                    <span>{product.category}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-muted-foreground">Origin:</span>
                    <span>{product.flag} {product.country}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-muted-foreground">Shipping:</span>
                    <span>{product.shipping}</span>
                  </div>
                </div>
              </CardContent>
            </Card>
          </div>
        </div>
      </div>
    </div>
  );
};

export default ProductDetail;
