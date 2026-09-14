import { createConfig, http, webSocket } from "wagmi";
import { injected } from "wagmi/connectors";
import { activeChain } from "./chains";

export const wagmiConfig = createConfig({
  chains: [activeChain],
  connectors: [injected()],
  transports: {
    [activeChain.id]: http(),
  },
  ssr: true,
});

declare module "wagmi" {
  interface Register {
    config: typeof wagmiConfig;
  }
}

export { webSocket };
