import { signData } from './rpc';
import { Provider } from '@ethersproject/providers';
import { IPool__factory } from '../typechain';

interface TradeQuoteBase {
  provider: string;
  taker: string;
  price: number | string;
  size: number | string;
  isBuy: boolean;
  deadline: number;
}

export interface TradeQuote extends TradeQuoteBase {
  nonce: number;
}

export interface TradeQuoteNonceOptional extends TradeQuoteBase {
  nonce?: number;
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
  quote: TradeQuoteNonceOptional,
) {
  const domain: Domain = {
    name: 'Premia',
    version: '1',
    chainId: (await w3Provider.getNetwork()).chainId,
    verifyingContract: poolAddress,
  };

  // Query current nonce for taker from contract, if nonce is not specified
  if (quote.nonce === undefined) {
    quote.nonce = (
      await IPool__factory.connect(poolAddress, w3Provider).getQuoteNonce(
        quote.taker,
      )
    ).toNumber();
  }

  const message: TradeQuote = {
    ...(quote as TradeQuote),
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
  const sig = await signData(w3Provider, quote.provider, typedData);

  return { ...sig, ...message };
}
