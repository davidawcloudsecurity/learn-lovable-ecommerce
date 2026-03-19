# Welcome to your Lovable project

### How to create wordpress database and create tables for mock product
To use the mock products in a PostgreSQL `wordpress` database, you'll need to:

---

## ✅ 1. **Create the `wordpress` Database (if not exists)**

First, open `psql` as the `postgres` user:

```bash
# 1. Run PostgreSQL Docker container
docker run --name postgres-db \
  -e POSTGRES_DB=shop_db \
  -e POSTGRES_USER=shop_user \
  -e POSTGRES_PASSWORD=shop_password \
  -p 5432:5432 \
  -d postgres:15

# 2. Wait a few seconds for PostgreSQL to start, then connect to create the table
docker exec -it postgres-db psql -U shop_user -d shop_db

# 3. In the PostgreSQL shell, create the products table:
CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    price DECIMAL(10,2) NOT NULL,
    original_price DECIMAL(10,2),
    image VARCHAR(255),
    country VARCHAR(100),
    flag VARCHAR(10),
    rating DECIMAL(3,2),
    reviews INTEGER,
    shipping VARCHAR(255),
    category VARCHAR(100)
);

# 4. Insert the mock data
INSERT INTO products (name, price, original_price, image, country, flag, rating, reviews, shipping, category) VALUES
('MacBook Pro', 2500.00, 2800.00, 'photo-1647805256812-ccb927cf1f67', 'USA', '🇺🇸', 4.8, 1250, 'Free shipping', 'Electronics'),
('Lamp Shade', 25.00, 35.00, 'photo-1694353560850-436cb191fb8c', 'Italy', '🇮🇹', 4.2, 89, '$5.99 shipping', 'Home & Garden'),
('Laser Printer', 150.00, 199.00, 'photo-1625961332771-3f40b0e2bdcf', 'Japan', '🇯🇵', 4.5, 456, 'Free shipping', 'Electronics'),
('Laptop Stand', 45.00, 60.00, 'photo-1623251606108-512c7c4a3507', 'Germany', '🇩🇪', 4.3, 234, '$3.99 shipping', 'Electronics'),
('LED Light Bulb', 12.00, 18.00, 'photo-1553213134-f60afad82ceb', 'China', '🇨🇳', 4.1, 567, 'Free shipping', 'Home & Garden'),
('Luggage Set', 120.00, 160.00, 'photo-1708403120467-1715bb6840df', 'France', '🇫🇷', 4.6, 123, '$8.99 shipping', 'Travel'),
('Camping Lantern', 35.00, 50.00, 'photo-1570739260082-39a84dae80c8', 'Canada', '🇨🇦', 4.4, 198, 'Free shipping', 'Outdoor');

# 5. Exit PostgreSQL shell
\q

---

## ✅ 5. **Verify**

Run:

```sql
SELECT * FROM products;
```

You should see your rows.

---

### ✅ Optional: From Node.js

If you're loading from code, insert the mock array using your `pg` client like:

```js
const insertProduct = `
  INSERT INTO products
    (name, price, original_price, image, country, flag, rating, reviews, shipping, category)
  VALUES
    ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
`;

for (const p of mockProducts) {
  await pool.query(insertProduct, [
    p.name, p.price, p.originalPrice, p.image, p.country, p.flag,
    p.rating, p.reviews, p.shipping, p.category
  ]);
}
```
## Project info

**URL**: https://lovable.dev/projects/a9a91029-a853-4bb8-b915-13ab750793f5

## How can I edit this code?

There are several ways of editing your application.

**Use Lovable**

Simply visit the [Lovable Project](https://lovable.dev/projects/a9a91029-a853-4bb8-b915-13ab750793f5) and start prompting.

Changes made via Lovable will be committed automatically to this repo.

**Use your preferred IDE**

If you want to work locally using your own IDE, you can clone this repo and push changes. Pushed changes will also be reflected in Lovable.

The only requirement is having Node.js & npm installed - [install with nvm](https://github.com/nvm-sh/nvm#installing-and-updating)

Follow these steps:
```
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
nvm install 15.0.0
node -e "console.log('Running Node.js ' + process.version)"
nvm install-latest-npm
```
```sh
# Step 1: Clone the repository using the project's Git URL.
git clone <YOUR_GIT_URL>

# Step 2: Navigate to the project directory.
cd <YOUR_PROJECT_NAME>

# Step 3: Install the necessary dependencies.
npm i

# Step 4: Start the development server with auto-reloading and an instant preview.
npm run dev

# Step 5: Start the api server (e.g., using Express).
npm install express cors

# Step 6: Run the backend
node server.js
```

Test it
```
http://localhost:3001/api/search/suggestions?q=lap
```
You should get JSON like:

```
{
  "suggestions": ["laptop", "lamp"]
}
```

**Edit a file directly in GitHub**

- Navigate to the desired file(s).
- Click the "Edit" button (pencil icon) at the top right of the file view.
- Make your changes and commit the changes.

**Use GitHub Codespaces**

- Navigate to the main page of your repository.
- Click on the "Code" button (green button) near the top right.
- Select the "Codespaces" tab.
- Click on "New codespace" to launch a new Codespace environment.
- Edit files directly within the Codespace and commit and push your changes once you're done.

## What technologies are used for this project?

This project is built with:

- Vite
- TypeScript
- React
- shadcn-ui
- Tailwind CSS

## How can I deploy this project?

Simply open [Lovable](https://lovable.dev/projects/a9a91029-a853-4bb8-b915-13ab750793f5) and click on Share -> Publish.

## Can I connect a custom domain to my Lovable project?

Yes, you can! 

To connect a domain, navigate to Project > Settings > Domains and click Connect Domain.

Read more here: [Setting up a custom domain](https://docs.lovable.dev/tips-tricks/custom-domain#step-by-step-guide)
