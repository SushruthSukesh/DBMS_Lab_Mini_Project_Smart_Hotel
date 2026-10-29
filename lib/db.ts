import mysql, { Pool } from "mysql2/promise";
import { MongoClient, Db } from "mongodb";

let mysqlPool: Pool | undefined;
let mongoClient: MongoClient | undefined;

export function getMySQL(): Pool {
  if (!process.env.MYSQL_URL) {
    throw new Error("MYSQL_URL is not configured. Copy .env.example to .env.local.");
  }
  mysqlPool ??= mysql.createPool({
    uri: process.env.MYSQL_URL,
    connectionLimit: 10,
    namedPlaceholders: true,
    connectTimeout: 5000
  });
  return mysqlPool;
}

export async function getMongoDB(): Promise<Db> {
  if (!process.env.MONGODB_URI) {
    throw new Error("MONGODB_URI is not configured. Copy .env.example to .env.local.");
  }
  mongoClient ??= new MongoClient(process.env.MONGODB_URI);
  await mongoClient.connect();
  return mongoClient.db(process.env.MONGODB_DB ?? "smart_hotel_management");
}
