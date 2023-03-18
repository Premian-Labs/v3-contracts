import { Premia } from '../../typechain';
import { ethers } from 'ethers';
import { Interface } from '@ethersproject/abi';

export enum FacetCutAction {
  ADD,
  REPLACE,
  REMOVE,
}

export interface FacetCut {
  target: string;
  action: FacetCutAction;
  selectors: string[];
}

export async function diamondCut(
  diamond: Premia,
  contractAddress: string,
  contractInterface: Interface,
  excludeList: string[] = [],
  action: number = 0,
) {
  const registeredSelectors: string[] = [];
  const facetCuts: FacetCut[] = [
    {
      target: contractAddress,
      action: action,
      selectors: getSelectors(contractInterface, excludeList).map((fn) => {
        const sl = contractInterface.getSighash(fn);
        registeredSelectors.push(sl);
        return sl;
      }),
    },
  ];

  const tx = await diamond.diamondCut(
    facetCuts,
    ethers.constants.AddressZero,
    '0x',
  );
  await tx.wait(1);

  return registeredSelectors;
}

export function getSelectors(
  contractInterface: Interface,
  excludeList: string[] = [],
) {
  return Object.keys(contractInterface.functions)
    .filter((fn) => !excludeList.includes(contractInterface.getSighash(fn)))
    .map((el) => contractInterface.getSighash(el));
}
