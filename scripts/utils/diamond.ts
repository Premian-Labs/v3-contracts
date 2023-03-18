import { Premia } from '../../typechain';
import { ethers } from 'ethers';
import { Interface } from '@ethersproject/abi';

export async function diamondCut(
  diamond: Premia,
  contractAddress: string,
  contractInterface: Interface,
  excludeList: string[] = [],
  action: number = 0,
) {
  const registeredSelectors: string[] = [];
  const facetCuts = [
    {
      target: contractAddress,
      action: action,
      selectors: Object.keys(contractInterface.functions)
        .filter((fn) => !excludeList.includes(contractInterface.getSighash(fn)))
        .map((fn) => {
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
