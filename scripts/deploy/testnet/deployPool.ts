import { PoolFactory__factory } from '../../../typechain';
import { BigNumber } from 'ethers';
import { parseEther } from 'ethers/lib/utils';
import { ethers } from 'hardhat';
import { getValidMaturity, initialize, PoolKey } from '../../utils';

async function main() {
  const [deployer] = await ethers.getSigners();
  let { deployment } = await initialize(deployer);

  const poolFactory = PoolFactory__factory.connect(
    deployment.core.PoolFactoryProxy.address,
    deployer,
  );
  const poolKey: PoolKey = {
    base: deployment.tokens.testWETH,
    quote: deployment.tokens.USDC,
    oracleAdapter: deployment.core.ChainlinkAdapterProxy.address,
    strike: parseEther('2000'),
    maturity: BigNumber.from(await getValidMaturity(1, 'months')),
    isCallPool: true,
  };

  await poolFactory.deployPool(poolKey, {
    gasLimit: 1200000, // Fails to properly estimate gas limit
  });
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
