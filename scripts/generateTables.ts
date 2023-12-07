import { ChainID, generateTables } from './utils';

async function main() {
  const chain = ChainID.Arbitrum;
  await generateTables(chain, true);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
