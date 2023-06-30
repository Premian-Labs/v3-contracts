import { signData } from './rpc';
import { QuoteOB } from './types';
import { Provider } from '@ethersproject/providers';
import {
  defaultAbiCoder,
  keccak256,
  solidityPack,
  toUtf8Bytes,
} from 'ethers/lib/utils';

interface QuoteOBMessage {
  provider: string;
  taker: string;
  price: string;
  size: string;
  isBuy: boolean;
  deadline: string;
  salt: string;
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

export async function signQuoteOB(
  w3Provider: Provider,
  poolAddress: string,
  quoteOB: QuoteOB,
) {
  const domain: Domain = {
    name: 'Premia',
    version: '1',
    chainId: (await w3Provider.getNetwork()).chainId,
    verifyingContract: poolAddress,
  };

  const message: QuoteOBMessage = {
    ...quoteOB,
    price: quoteOB.price.toString(),
    size: quoteOB.size.toString(),
    deadline: quoteOB.deadline.toString(),
    salt: quoteOB.salt.toString(),
  };

  const typedData = {
    types: {
      EIP712Domain,
      FillQuoteOB: [
        { name: 'provider', type: 'address' },
        { name: 'taker', type: 'address' },
        { name: 'price', type: 'uint256' },
        { name: 'size', type: 'uint256' },
        { name: 'isBuy', type: 'bool' },
        { name: 'deadline', type: 'uint256' },
        { name: 'salt', type: 'uint256' },
      ],
    },
    primaryType: 'FillQuoteOB',
    domain,
    message,
  };
  const sig = await signData(w3Provider, quoteOB.provider, typedData);

  return { ...sig, ...message };
}

export async function calculateQuoteOBHash(
  w3Provider: Provider,
  quoteOB: QuoteOB,
  poolAddress: string,
) {
  const FILL_QUOTE_OB_TYPE_HASH = keccak256(
    toUtf8Bytes(
      'FillQuoteOB(address provider,address taker,uint256 price,uint256 size,bool isBuy,uint256 deadline,uint256 salt)',
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
      ],
      [
        FILL_QUOTE_OB_TYPE_HASH,
        quoteOB.provider,
        quoteOB.taker,
        quoteOB.price,
        quoteOB.size,
        quoteOB.isBuy,
        quoteOB.deadline,
        quoteOB.salt,
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
