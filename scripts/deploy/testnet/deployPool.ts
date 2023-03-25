import { ethers } from 'hardhat';
import { PoolFactory__factory } from '../../../typechain';

import goerliAddresses from '../../../utils/deployment/goerli.json';
import { parseEther } from 'ethers/lib/utils';
import { PoolKey } from '../../../utils/sdk/types';
import { BigNumber } from 'ethers';
import { getValidMaturity } from '../../../utils/time';

async function main() {
  const [deployer] = await ethers.getSigners();

  const poolFactory = PoolFactory__factory.connect(
    goerliAddresses.PoolFactoryProxy,
    deployer,
  );
  const poolKey: PoolKey = {
    base: goerliAddresses.tokens.testWETH,
    quote: goerliAddresses.tokens.USDC,
    oracleAdapter: goerliAddresses.ChainlinkAdapterProxy,
    strike: parseEther('2000'),
    maturity: BigNumber.from(await getValidMaturity(1, 'months', false)),
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
