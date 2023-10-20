import arbitrum from '../utils/deployment/arbitrum/metadata.json';
import { arbitrumFeeds } from '../utils/addresses';
import { ChainlinkAdapter__factory } from '../typechain';
import { ethers } from 'hardhat';
import { proposeOrSendTransaction } from './utils/safe';

async function main() {
  const [deployer, proposer] = await ethers.getSigners();

  const adapter = ChainlinkAdapter__factory.connect(
    arbitrum.core.ChainlinkAdapterProxy.address,
    deployer,
  );

  const feed = arbitrumFeeds.filter(
    (feed) => feed.token === arbitrum.tokens.MIM,
  );

  const transaction =
    await adapter.populateTransaction.batchRegisterFeedMappings(feed);

  await proposeOrSendTransaction(true, arbitrum.addresses.treasury, proposer, [
    transaction,
  ]);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
