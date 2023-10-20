import arbitrum from '../utils/deployment/arbitrum/metadata.json';
import { arbitrumFeeds } from '../utils/addresses';
import { ChainlinkAdapter__factory } from '../typechain';
import { ethers } from 'hardhat';

async function main() {
  const [deployer] = await ethers.getSigners();

  await ChainlinkAdapter__factory.connect(
    arbitrum.core.ChainlinkAdapterProxy.address,
    deployer,
  ).batchRegisterFeedMappings(arbitrumFeeds.slice(4));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
