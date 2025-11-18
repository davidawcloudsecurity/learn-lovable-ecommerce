import express from 'express';
import cors from 'cors';
import pkg from 'pg';
import dotenv from 'dotenv';
dotenv.config();

const { Pool } = pkg;

const app = express();
const PORT = 3001;

app.use(cors()); // Allow requests from Vite dev server
app.use(express.json());

// PostgreSQL connection pool
const pool = new Pool({
  host: process.env.POSTGRES_HOST || 'your-aws-rds-endpoint.amazonaws.com',
  port: process.env.POSTGRES_PORT || 5432,
  database: process.env.POSTGRES_DB || 'your_database_name',
  user: process.env.POSTGRES_USER || 'your_username',
  password: process.env.POSTGRES_PASSWORD || 'your_password',
  ssl: {
    rejectUnauthorized: false // AWS RDS requires SSL
  }
});

// Test database connection
pool.connect((err, client, release) => {
  if (err) {
    console.error('❌ Error connecting to PostgreSQL:', err);
  } else {
    console.log('✅ Connected to PostgreSQL database');
    release();
  }
});

// Mock products with complete data structure
const mockProducts = [
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
    category: 'Electronics'
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
    category: 'Home & Garden'
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
    category: 'Electronics'
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
    category: 'Electronics'
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
    category: 'Home & Garden'
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
    category: 'Travel'
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
    category: 'Outdoor'
  }
];

// Suggestion endpoint
app.get('/api/search/suggestions', async (req, res) => {
  try {
    const q = req.query.q?.toLowerCase() || '';
    const query = `
      SELECT DISTINCT name 
      FROM products 
      WHERE LOWER(name) LIKE $1 OR LOWER(category) LIKE $1
      LIMIT 10
    `;
    const result = await pool.query(query, [`%${q}%`]);
    const suggestions = result.rows.map(row => row.name.toLowerCase());
    res.json({ suggestions });
  } catch (error) {
    console.error('Database error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Search endpoint
app.get('/api/search', async (req, res) => {
  try {
    const q = req.query.q?.toLowerCase() || '';
    const limit = parseInt(req.query.limit) || 12;
    const offset = parseInt(req.query.offset) || 0;
    
    // Count total results
    const countQuery = `
      SELECT COUNT(*) as total 
      FROM products 
      WHERE LOWER(name) LIKE $1 OR LOWER(category) LIKE $1
    `;
    const countResult = await pool.query(countQuery, [`%${q}%`]);
    const total = parseInt(countResult.rows[0].total);
    
    // Get paginated results
    const dataQuery = `
      SELECT * FROM products 
      WHERE LOWER(name) LIKE $1 OR LOWER(category) LIKE $1
      ORDER BY id
      LIMIT $2 OFFSET $3
    `;
    const dataResult = await pool.query(dataQuery, [`%${q}%`, limit, offset]);
    
    res.json({
      query: q,
      results: dataResult.rows,
      total: total,
      limit: limit,
      offset: offset
    });
  } catch (error) {
    console.error('Database error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.listen(PORT, () => {
  console.log(`✅ API server is running at http://localhost:${PORT}`);
});
