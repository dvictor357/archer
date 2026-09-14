import { isHex } from "viem";
import { PayRequest } from "@/components/PayRequest";

export default async function PayPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!isHex(id) || id.length !== 66) {
    return <p className="text-red-400">Invalid request id.</p>;
  }
  return <PayRequest id={id} />;
}
