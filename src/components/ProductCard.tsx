import React from 'react';
import { Button } from '@/components/ui/button';
import { ShoppingCart, Package } from 'lucide-react';
import { useNavigate } from 'react-router-dom';

const IMAGES_PATH = '/assets/images/';

interface ProductCardProps {
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
}

const ProductCard: React.FC<ProductCardProps> = ({
  id,
  name,
  price,
  originalPrice,
  image,
  country,
  flag,
  rating,
  reviews,
  shipping
}) => {
  const navigate = useNavigate();

  const handleAddToCart = () => {
    // Navigate to checkout with product data as URL parameters
    const productData = {
      id,
      name,
      price,
      originalPrice,
      image,
      country,
      flag,
      rating,
      reviews,
      shipping
    };
    
    // Encode product data as URL parameters
    const params = new URLSearchParams({
      productId: id.toString(),
      productName: name,
      productPrice: price.toString(),
      productImage: image,
      productCountry: country,
      productFlag: flag,
      productRating: rating.toString(),
      productReviews: reviews.toString(),
      productShipping: shipping,
      ...(originalPrice && { originalPrice: originalPrice.toString() })
    });
    
    navigate(`/checkout?${params.toString()}`);
  };

  return (
    <div className="bg-white rounded-lg shadow-md hover:shadow-xl transition-all duration-300 hover:scale-105 group">
      <div className="relative overflow-hidden rounded-t-lg">
        <img
          src={`${IMAGES_PATH}${image}`}
          alt={name}
          className="w-full h-48 object-cover group-hover:scale-110 transition-transform duration-300"
        />
        {originalPrice && (
          <div className="absolute top-2 left-2 bg-red-500 text-white px-2 py-1 rounded text-sm font-bold">
            -{Math.round(((originalPrice - price) / originalPrice) * 100)}%
          </div>
        )}
        <div className="absolute top-2 right-2 flex items-center bg-white/90 backdrop-blur-sm rounded px-2 py-1">
          <span className="text-lg mr-1">{flag}</span>
          <span className="text-xs font-medium text-gray-600">{country}</span>
        </div>
      </div>
      
      <div className="p-4">
        <h3
          className="font-semibold text-gray-900 mb-2 line-clamp-2 hover:text-blue-600 cursor-pointer"
          onClick={() => navigate(`/product/${id}`)} // Navigate to product detail page when clicked
        >
          {name}
        </h3>
        
        <div className="flex items-center mb-2">
          <div className="flex text-yellow-400">
            {[...Array(5)].map((_, i) => (
              <span key={i} className={i < Math.floor(rating) ? "★" : "☆"}>★</span>
            ))}
          </div>
          <span className="text-sm text-gray-500 ml-2">({reviews})</span>
        </div>

        <div className="flex items-center justify-between mb-3">
          <div className="flex items-center space-x-2">
            <span className="text-2xl font-bold text-blue-600">${price}</span>
            {originalPrice && (
              <span className="text-sm text-gray-500 line-through">${originalPrice}</span>
            )}
          </div>
        </div>

        <div className="flex items-center text-sm text-gray-600 mb-3">
          <Package className="h-4 w-4 mr-1" />
          <span>{shipping}</span>
        </div>

        <Button 
          className="w-full bg-blue-600 hover:bg-blue-700 text-white"
          onClick={handleAddToCart}
        >
          <ShoppingCart className="h-4 w-4 mr-2" />
          Add to Cart
        </Button>
      </div>
    </div>
  );
};

export default ProductCard;
