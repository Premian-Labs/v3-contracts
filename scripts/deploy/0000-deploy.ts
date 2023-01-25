import { ethers } from 'hardhat';
import { PoolUtil } from '../../utils/PoolUtil';

async function main() {
  const [deployer] = await ethers.getSigners();

  const weth = '0x82aF49447D8a07e3bd95BD0d56f35241523fBab1';

  await PoolUtil.deploy(deployer, weth, true);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
