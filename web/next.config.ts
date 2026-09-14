import type { NextConfig } from "next";
import path from "node:path";

const nextConfig: NextConfig = {
  // chains.json lives one level up and is shared with contracts/.
  turbopack: { root: path.join(__dirname, "..") },
};

export default nextConfig;
