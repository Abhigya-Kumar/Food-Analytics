"""
Zomato Sales Analysis - Synthetic Data Generator
--------------------------------------------------
Generates a realistic, internally-consistent food-delivery dataset
(customers, restaurants, orders) for the portfolio project.

Note: This is SYNTHETIC data generated for portfolio/learning purposes.
It mimics the shape and patterns of real Zomato-style order data but
contains no real customer, restaurant, or transaction information.

Run: python generate_data.py
Outputs CSVs into ../data/
"""

import numpy as np
import pandas as pd
from datetime import datetime, timedelta
import os

SEED = 42
rng = np.random.default_rng(SEED)

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "data")
os.makedirs(OUT_DIR, exist_ok=True)

# ------------------------------------------------------------------
# 1. CITIES  (weighted so metro cities dominate order volume, like reality)
# ------------------------------------------------------------------
cities = [
    ("Delhi NCR",   0.22),
    ("Mumbai",      0.19),
    ("Bengaluru",   0.18),
    ("Hyderabad",   0.12),
    ("Pune",        0.10),
    ("Kolkata",     0.08),
    ("Chennai",     0.07),
    ("Ahmedabad",   0.04),
]
city_names = [c[0] for c in cities]
city_weights = np.array([c[1] for c in cities])
city_weights = city_weights / city_weights.sum()

# ------------------------------------------------------------------
# 2. CUISINES  (with a typical avg cost-for-two range)
# ------------------------------------------------------------------
cuisines = {
    "North Indian":   (300, 700),
    "South Indian":   (150, 400),
    "Chinese":        (250, 550),
    "Fast Food":      (150, 350),
    "Biryani":        (200, 500),
    "Italian":        (400, 900),
    "Desserts":       (100, 300),
    "Bakery":         (100, 300),
    "Mughlai":        (350, 750),
    "Continental":    (450, 950),
    "Street Food":    (100, 250),
    "Healthy Food":   (300, 650),
}
cuisine_names = list(cuisines.keys())

# ------------------------------------------------------------------
# 3. RESTAURANTS
# ------------------------------------------------------------------
N_RESTAURANTS = 60
name_prefixes = ["Spice", "Royal", "Urban", "The Great", "Tandoori", "Curry", "Wok", "Biryani House",
                  "Punjabi", "Southern", "Sultan's", "Green Leaf", "Corner", "Golden", "Zaika",
                  "Bombay", "Chennai Express", "Hyderabadi", "Bengal", "Cafe", "Truffle", "Spicy Bites"]
name_suffixes = ["Kitchen", "Restaurant", "Dhaba", "Cafe", "Junction", "Bistro", "House", "Point",
                  "Hub", "Corner", "Express", "Adda", "Treat", "Delights", "Bites", "Kitchen & Co."]

restaurants = []
for rid in range(1, N_RESTAURANTS + 1):
    cuisine = rng.choice(cuisine_names)
    lo, hi = cuisines[cuisine]
    city = rng.choice(city_names, p=city_weights)
    rname = f"{rng.choice(name_prefixes)} {rng.choice(name_suffixes)}"
    cost_for_two = int(rng.integers(lo, hi))
    quality = rng.normal(0, 1)
    avg_rating = np.clip(3.9 + quality * 0.35, 2.8, 4.9)
    is_veg_only = rng.random() < 0.28
    onboard_year = int(rng.choice([2019, 2020, 2021, 2022, 2023], p=[0.15, 0.2, 0.25, 0.25, 0.15]))
    restaurants.append({
        "restaurant_id": rid,
        "restaurant_name": f"{rname} {rid}",
        "city": city,
        "cuisine": cuisine,
        "cost_for_two": cost_for_two,
        "is_veg_only": is_veg_only,
        "avg_rating": round(avg_rating, 1),
        "onboarded_year": onboard_year,
        "_quality": quality,
    })

restaurants_df = pd.DataFrame(restaurants)

# ------------------------------------------------------------------
# 4. CUSTOMERS
# ------------------------------------------------------------------
N_CUSTOMERS = 2500
first_names = ["Aarav", "Vivaan", "Aditya", "Vihaan", "Arjun", "Sai", "Reyansh", "Krishna", "Ishaan",
               "Rohan", "Ananya", "Diya", "Aadhya", "Isha", "Myra", "Anika", "Kiara", "Saanvi", "Meera",
               "Neha", "Priya", "Riya", "Zara", "Kabir", "Aryan", "Dev", "Karthik", "Rahul", "Sneha", "Pooja"]
last_names = ["Sharma", "Verma", "Gupta", "Reddy", "Nair", "Iyer", "Khan", "Singh", "Patel", "Das",
              "Chatterjee", "Mehta", "Joshi", "Kapoor", "Rao", "Bose", "Malhotra", "Chauhan", "Pillai"]

signup_start = datetime(2022, 1, 1)
signup_end = datetime(2024, 11, 30)
signup_range_days = (signup_end - signup_start).days

customers = []
for cid in range(1, N_CUSTOMERS + 1):
    city = rng.choice(city_names, p=city_weights)
    signup_date = signup_start + timedelta(days=int(rng.integers(0, signup_range_days)))
    is_premium = rng.random() < 0.18
    activity = rng.gamma(shape=2.0, scale=1.2)
    customers.append({
        "customer_id": cid,
        "customer_name": f"{rng.choice(first_names)} {rng.choice(last_names)}",
        "city": city,
        "signup_date": signup_date.date().isoformat(),
        "is_premium_member": is_premium,
        "_activity": activity,
    })

customers_df = pd.DataFrame(customers)

# ------------------------------------------------------------------
# 5. ORDERS  (fact table)
# ------------------------------------------------------------------
ORDER_START = datetime(2023, 1, 1)
ORDER_END = datetime(2024, 12, 31)

N_ORDERS = 9000
payment_methods = ["UPI", "Credit/Debit Card", "Net Banking", "Cash on Delivery", "Wallet"]
payment_weights = [0.45, 0.22, 0.08, 0.15, 0.10]

statuses = ["Delivered", "Cancelled by Customer", "Cancelled by Restaurant"]
status_weights = [0.90, 0.06, 0.04]

cust_ids = customers_df["customer_id"].values
cust_probs = customers_df["_activity"].values
cust_probs = cust_probs / cust_probs.sum()

rest_ids = restaurants_df["restaurant_id"].values
rest_pop = np.exp(restaurants_df["_quality"].values * 0.35)  # gentle popularity skew

# pre-compute, per city, the restaurant ids + normalized popularity weights
# (food delivery is local: customers overwhelmingly order from their own city)
city_rest_ids = {}
city_rest_probs = {}
for c in city_names:
    mask = (restaurants_df["city"] == c).values
    ids_in_city = rest_ids[mask]
    if len(ids_in_city) == 0:
        continue
    pop_in_city = rest_pop[mask]
    city_rest_ids[c] = ids_in_city
    city_rest_probs[c] = pop_in_city / pop_in_city.sum()

all_rest_probs = rest_pop / rest_pop.sum()

orders = []
order_id = 100001

for i in range(N_ORDERS):
    cust_idx = rng.choice(len(cust_ids), p=cust_probs)
    customer_id = cust_ids[cust_idx]
    cust_row = customers_df.iloc[cust_idx]
    cust_signup = datetime.fromisoformat(cust_row["signup_date"])
    cust_city = cust_row["city"]

    if cust_city in city_rest_ids and rng.random() < 0.92:
        restaurant_id = rng.choice(city_rest_ids[cust_city], p=city_rest_probs[cust_city])
    else:
        restaurant_id = rng.choice(rest_ids, p=all_rest_probs)
    rest_row = restaurants_df[restaurants_df["restaurant_id"] == restaurant_id].iloc[0]

    earliest = max(ORDER_START, cust_signup)
    if earliest >= ORDER_END:
        earliest = ORDER_START
    span = (ORDER_END - earliest).days
    if span <= 0:
        span = 30
    day_offset = int(rng.triangular(0, span, span))
    order_date = earliest + timedelta(days=day_offset)

    if order_date.weekday() < 5 and rng.random() < 0.15:
        shift = (5 - order_date.weekday()) % 7
        order_date = order_date + timedelta(days=shift)
        if order_date > ORDER_END:
            order_date = order_date - timedelta(days=7)

    hour_bucket = rng.choice(["lunch", "dinner", "other"], p=[0.30, 0.45, 0.25])
    if hour_bucket == "lunch":
        hour = int(rng.integers(12, 15))
    elif hour_bucket == "dinner":
        hour = int(rng.integers(19, 23))
    else:
        hour = int(rng.integers(6, 23))
    minute = int(rng.integers(0, 60))
    order_datetime = order_date.replace(hour=hour, minute=minute)

    base_cost = rest_row["cost_for_two"] / 2
    item_count = int(rng.integers(1, 5))
    order_value = round(base_cost * item_count * rng.uniform(0.8, 1.3), 2)

    discount_pct = rng.choice([0, 0, 0, 0.10, 0.15, 0.20, 0.25], p=[0.45, 0.1, 0.05, 0.15, 0.1, 0.1, 0.05])
    discount_amount = round(order_value * discount_pct, 2)
    delivery_fee = round(rng.choice([0, 20, 25, 30, 40], p=[0.25, 0.25, 0.2, 0.2, 0.1]), 2)
    taxable_amount = order_value - discount_amount
    taxes = round(taxable_amount * 0.05, 2)
    total_amount = round(taxable_amount + taxes + delivery_fee, 2)

    status = rng.choice(statuses, p=status_weights)

    if status == "Delivered":
        metro_penalty = {"Delhi NCR": 6, "Mumbai": 8, "Bengaluru": 7, "Kolkata": 5,
                          "Hyderabad": 3, "Pune": 2, "Chennai": 4, "Ahmedabad": 1}.get(rest_row["city"], 3)
        delivery_time = int(np.clip(rng.normal(32 + metro_penalty, 8), 15, 75))
        rating_base = rest_row["avg_rating"] - (0.01 * max(0, delivery_time - 35))
        order_rating = np.clip(rng.normal(rating_base, 0.6), 1, 5)
        order_rating = round(order_rating * 2) / 2
        if rng.random() < 0.20:
            order_rating = np.nan
    else:
        delivery_time = np.nan
        order_rating = np.nan
        delivery_fee = 0
        taxes = 0
        total_amount = 0

    payment_method = rng.choice(payment_methods, p=payment_weights)

    orders.append({
        "order_id": order_id,
        "customer_id": int(customer_id),
        "restaurant_id": int(restaurant_id),
        "order_datetime": order_datetime.strftime("%Y-%m-%d %H:%M:%S"),
        "order_value": order_value,
        "discount_amount": discount_amount,
        "delivery_fee": delivery_fee,
        "taxes": taxes,
        "total_amount": total_amount,
        "payment_method": payment_method,
        "delivery_time_mins": delivery_time if not pd.isna(delivery_time) else "",
        "customer_rating": order_rating if not pd.isna(order_rating) else "",
        "order_status": status,
    })
    order_id += 1

orders_df = pd.DataFrame(orders)
orders_df = orders_df.sort_values("order_datetime").reset_index(drop=True)
orders_df["order_id"] = range(100001, 100001 + len(orders_df))

# ------------------------------------------------------------------
# 6. CLEAN UP + EXPORT
# ------------------------------------------------------------------
restaurants_export = restaurants_df.drop(columns=["_quality"]).copy()
restaurants_export["is_veg_only"] = restaurants_export["is_veg_only"].map({True: "Yes", False: "No"})

customers_export = customers_df.drop(columns=["_activity"]).copy()
customers_export["is_premium_member"] = customers_export["is_premium_member"].map({True: "Yes", False: "No"})

customers_export.to_csv(os.path.join(OUT_DIR, "zomato_customers.csv"), index=False)
restaurants_export.to_csv(os.path.join(OUT_DIR, "zomato_restaurants.csv"), index=False)
orders_df.to_csv(os.path.join(OUT_DIR, "zomato_orders.csv"), index=False)

print(f"customers: {len(customers_export)} rows")
print(f"restaurants: {len(restaurants_export)} rows")
print(f"orders: {len(orders_df)} rows")
print(f"date range: {orders_df['order_datetime'].min()} -> {orders_df['order_datetime'].max()}")
print(f"total delivered revenue: {orders_df.loc[orders_df.order_status=='Delivered','total_amount'].sum():,.2f}")
