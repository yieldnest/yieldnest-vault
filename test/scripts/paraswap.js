  const {constructSimpleSDK} = require("@paraswap/sdk");
  const axios = require("axios");
  const objectHash = require("object-hash");
  const { ethers } = require("ethers");
  const fs = require("fs");
  const path = require("path");
  
  const args = process.argv.slice(2);
  
  const CHAIN_ID = args[0];
  const FROM = args[1];
  const TO = args[2];
  const AMOUNT = args[3];
  const USER_ADDRESS = args[4];
  const MAX_SLIPPAGE = Number(args[5]);
  const FROM_DECIMALS = Number(args[6]);
  const TO_DECIMALS = Number(args[7]);
  const UPDATE_PSP_CACHE = args[8] !== "false";
  
  // generate a hash for input parameters to cache response and not spam psp sdk
  const hash = objectHash(args);
  
  const paraSwapMin = constructSimpleSDK({chainId: CHAIN_ID, axios});
  
  async function main(from, to, amount, user) {
    // check cache and return cache if available
    const filePath = path.join(process.cwd(), "src/test/.pspcache", hash);
    if (fs.existsSync(filePath)) {
      const file = fs.readFileSync(filePath);
      process.stdout.write(file);
      return;
    }
  
    const priceRoute = await paraSwapMin.swap.getRate({
      srcToken: from,
      srcDecimals: FROM_DECIMALS,
      destToken: to,
      destDecimals: TO_DECIMALS,
      amount: amount,
      side: "SELL"
    });
  
    // add slippage on non exact side of the swap
    const srcAmount = priceRoute.srcAmount;
    let destAmount = BigInt(priceRoute.destAmount) * BigInt(10000 - MAX_SLIPPAGE) / BigInt(10000);
    destAmount = destAmount.toString();

    const txParams = await paraSwapMin.swap.buildTx(
      {
        srcToken: from,
        srcDecimals: FROM_DECIMALS,
        destToken: to,
        destDecimals: TO_DECIMALS,
        srcAmount,
        destAmount,
        priceRoute,
        userAddress: USER_ADDRESS,
        receiver: USER_ADDRESS,
        txOrigin: USER_ADDRESS,
        partner: "YieldNest",
      },
      { ignoreChecks: true }
    );
    
    const encodedData = ethers.AbiCoder.defaultAbiCoder().encode(
      ["(address,bytes)"],
      [[txParams.to, txParams.data]]
    );

    if (UPDATE_PSP_CACHE) {
      fs.writeFileSync(filePath, encodedData);
    }
    process.stdout.write(encodedData);
  }

  main(FROM, TO, AMOUNT, USER_ADDRESS);