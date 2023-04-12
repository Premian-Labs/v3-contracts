import { signData } from './rpc';
import { QuoteRFQ } from './types';
import { Provider } from '@ethersproject/providers';
import {
  defaultAbiCoder,
  keccak256,
  solidityPack,
  toUtf8Bytes,
} from 'ethers/lib/utils';

interface QuoteRFQMessage {
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

export async function signQuoteRFQ(
  w3Provider: Provider,
  poolAddress: string,
  quoteRFQ: QuoteRFQ,
) {
  const domain: Domain = {
    name: 'Premia',
    version: '1',
    chainId: (await w3Provider.getNetwork()).chainId,
    verifyingContract: poolAddress,
  };

  const message: QuoteRFQMessage = {
    ...quoteRFQ,
    price: quoteRFQ.price.toString(),
    size: quoteRFQ.size.toString(),
    deadline: quoteRFQ.deadline.toString(),
    salt: quoteRFQ.salt.toString(),
  };

  const typedData = {
    types: {
      EIP712Domain,
      FillQuoteRFQ: [
        { name: 'provider', type: 'address' },
        { name: 'taker', type: 'address' },
        { name: 'price', type: 'uint256' },
        { name: 'size', type: 'uint256' },
        { name: 'isBuy', type: 'bool' },
        { name: 'deadline', type: 'uint256' },
        { name: 'salt', type: 'uint256' },
      ],
    },
    primaryType: 'FillQuoteRFQ',
    domain,
    message,
  };
  const sig = await signData(w3Provider, quoteRFQ.provider, typedData);

  return { ...sig, ...message };
}

export async function calculateQuoteRFQHash(
  w3Provider: Provider,
  quoteRFQ: QuoteRFQ,
  poolAddress: string,
) {
  const FILL_QUOTE_RFQ_TYPE_HASH = keccak256(
    toUtf8Bytes(
      'FillQuoteRFQ(address provider,address taker,uint256 price,uint256 size,bool isBuy,uint256 deadline,uint256 salt)',
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
        FILL_QUOTE_RFQ_TYPE_HASH,
        quoteRFQ.provider,
        quoteRFQ.taker,
        quoteRFQ.price,
        quoteRFQ.size,
        quoteRFQ.isBuy,
        quoteRFQ.deadline,
        quoteRFQ.salt,
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
