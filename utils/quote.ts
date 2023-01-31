import { getChainId, signData } from './rpc';
import { Provider } from '@ethersproject/providers';

export interface TradeQuote {
  provider: string;
  taker: string;
  price: number | string;
  size: number | string;
  isBuy: boolean;
  nonce: number;
  deadline: number;
}

interface Domain {
  name: string;
  version: string;
  chainId: number;
  verifyingContract: string;
}

const EIP712Domain = [
  { name: 'name', type: 'string' },
  { name: 'version', type: 'string' },
  { name: 'chainId', type: 'uint256' },
  { name: 'verifyingContract', type: 'address' },
];

export async function signQuote(
  w3Provider: Provider,
  poolAddress: string,
  provider: string,
  taker: string,
  price: string | number,
  size: string | number,
  isBuy: boolean,
  deadline: number,
  nonce: number, // ToDo : Allow for it to be undefined and query directly from contract
) {
  const domain: Domain = {
    name: 'Premia',
    version: '1',
    chainId: (await w3Provider.getNetwork()).chainId,
    verifyingContract: poolAddress,
  };

  const message: TradeQuote = {
    provider,
    taker,
    price,
    size,
    isBuy,
    nonce,
    deadline,
  };

  const typedData = {
    types: {
      EIP712Domain,
      FillQuote: [
        { name: 'provider', type: 'address' },
        { name: 'taker', type: 'address' },
        { name: 'price', type: 'uint256' },
        { name: 'size', type: 'uint256' },
        { name: 'isBuy', type: 'bool' },
        { name: 'nonce', type: 'uint256' },
        { name: 'deadline', type: 'uint256' },
      ],
    },
    primaryType: 'FillQuote',
    domain,
    message,
  };
  const sig = await signData(w3Provider, provider, typedData);

  return { ...sig, ...message };
}
