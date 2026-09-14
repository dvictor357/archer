import { CreateRequest } from "@/components/CreateRequest";

export default function Home() {
  return (
    <div className="space-y-8">
      <section>
        <h1 className="text-3xl font-semibold tracking-tight">Aim. Release. Settled.</h1>
        <p className="mt-2 text-zinc-400">
          Create a USDC payment link on Arc. The payer settles in one transaction; you receive
          funds instantly with deterministic finality.
        </p>
      </section>
      <CreateRequest />
    </div>
  );
}
