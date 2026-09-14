import type { Metadata } from "next";
import Link from "next/link";
import "./globals.css";
import { Providers } from "./providers";
import { ConnectButton } from "@/components/ConnectButton";
import { activeConfig } from "@/lib/chains";

export const metadata: Metadata = {
  title: "Archer",
  description: "Aim. Release. Settled. USDC payment links on Arc.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className="min-h-screen bg-zinc-950 text-zinc-100 antialiased">
        <Providers>
          <header className="mx-auto flex max-w-2xl items-center justify-between px-4 py-5">
            <Link href="/" className="flex items-baseline gap-2">
              <span className="text-xl font-semibold tracking-tight">Archer</span>
              <span className="rounded-full border border-zinc-700 px-2 py-0.5 text-xs text-zinc-400">
                {activeConfig.name}
              </span>
            </Link>
            <ConnectButton />
          </header>
          <main className="mx-auto max-w-2xl px-4 pb-16">{children}</main>
        </Providers>
      </body>
    </html>
  );
}
