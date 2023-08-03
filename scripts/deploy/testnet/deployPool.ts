import { PoolFactory__factory } from '../../../typechain';
import arbitrumGoerliAddresses from '../../../utils/deployment/arbitrumGoerli.json';
import { PoolKey } from '../../../utils/sdk/types';
import { getValidMaturity } from '../../../utils/time';
import { BigNumber } from 'ethers';
import { parseEther } from 'ethers/lib/utils';
import { ethers } from 'hardhat';
import { ChainID, ContractAddresses } from '../../../utils/deployment/types';

async function main() {
  const [deployer] = await ethers.getSigners();
  const chainId = await deployer.getChainId();

  let addresses: ContractAddresses;

  if (chainId === ChainID.ArbitrumGoerli) {
    addresses = arbitrumGoerliAddresses;
  } else {
    throw new Error('ChainId not implemented');
  }

  const poolFactory = PoolFactory__factory.connect(
    addresses.PoolFactoryProxy,
    deployer,
  );
  const poolKey: PoolKey = {
    base: addresses.tokens.testWETH,
    quote: addresses.tokens.USDC,
    oracleAdapter: addresses.ChainlinkAdapterProxy,
    strike: parseEther('2000'),
    maturity: BigNumber.from(await getValidMaturity(1, 'months')),
    isCallPool: true,
  };

  const initFee = await poolFactory.initializationFee(poolKey);

  await poolFactory.deployPool(poolKey, {
    value: initFee.add(initFee.div(20)), // Fails for some reason if we pass the exact init fee
    gasLimit: 1200000, // Fails to properly estimate gas limit
  });
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
