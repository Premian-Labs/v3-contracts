import { signData } from './rpc';
import { Provider } from '@ethersproject/providers';
import { IPool__factory } from '../../typechain';
import { TradeQuote, TradeQuoteNonceOptional } from './types';
import {
  defaultAbiCoder,
  keccak256,
  solidityPack,
  toUtf8Bytes,
} from 'ethers/lib/utils';

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
  if (quote.categoryNonce === undefined) {
    quote.categoryNonce = (
      await IPool__factory.connect(
        poolAddress,
        w3Provider,
      ).getTradeQuoteCategoryNonce(quote.provider, quote.category)
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
        { name: 'category', type: 'uint256' },
        { name: 'categoryNonce', type: 'uint256' },
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

export async function calculateQuoteHash(
  w3Provider: Provider,
  quote: TradeQuote,
  poolAddress: string,
) {
  const FILL_QUOTE_TYPE_HASH = keccak256(
    toUtf8Bytes(
      'FillQuote(address provider,address taker,uint256 price,uint256 size,bool isBuy,uint256 category,uint256 categoryNonce,uint256 deadline)',
    ),
  );

  const EIP712_TYPE_HASH = keccak256(
    toUtf8Bytes(
      'EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)',
    ),
  );

  const domain: Domain = {
    name: 'Premia',
    version: '1',
    chainId: (await w3Provider.getNetwork()).chainId,
    verifyingContract: poolAddress,
  };

  const domainHash = keccak256(
    defaultAbiCoder.encode(
      ['bytes32', 'bytes32', 'bytes32', 'uint256', 'address'],
      [
        EIP712_TYPE_HASH,
        keccak256(toUtf8Bytes(domain.name)),
        keccak256(toUtf8Bytes(domain.version)),
        domain.chainId,
        domain.verifyingContract,
      ],
    ),
  );

  const structHash = keccak256(
    defaultAbiCoder.encode(
      [
        'bytes32',
        'address',
        'address',
        'uint256',
        'uint256',
        'bool',
        'uint256',
        'uint256',
        'uint256',
      ],
      [
        FILL_QUOTE_TYPE_HASH,
        quote.provider,
        quote.taker,
        quote.price,
        quote.size,
        quote.isBuy,
        quote.category,
        quote.categoryNonce,
        quote.deadline,
      ],
    ),
  );

  return keccak256(
    solidityPack(
      ['string', 'bytes32', 'bytes32'],
      ['\x19\x01', domainHash, structHash],
    ),
  );
}
