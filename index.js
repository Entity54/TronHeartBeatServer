'use strict';
require('dotenv').config();
const express = require('express');
const path = require('path');             
const http = require('http');     
const TronWeb = require('tronweb');

const will_artifact = require('./Abis/will.json');     
const willAbi = will_artifact.abi;

const willFactory_artifact = require('./Abis/willFactory.json');     
const willFactoryAbi = willFactory_artifact.abi;
const willFactoryAddress = "TTRLq8EXy5p1Tj1BziP6B9nCtz9DAuvnTp";

let tronWeb, willFactorySC;
// Server_PUBLICKEY = TQpTa1Y51hYHXqVYX5v4o3VjLneaX59BoC


const set_tronWeb = () => {
    console.log(`Setting up TronWeb`);
    const HttpProvider = TronWeb.providers.HttpProvider;
    const fullNode = new HttpProvider("https://api.nileex.io");
    const solidityNode = new HttpProvider("https://api.nileex.io");
    const eventServer = new HttpProvider("https://api.nileex.io");
    tronWeb = new TronWeb(fullNode,solidityNode,eventServer,process.env.Server_PRKEY);
}
const publicPath = path.join(__dirname,'./');       
const port = process.env.PORT || 3001;
var app = express();
app.use((req,res,next) => {
    next();
});
const server = http.createServer(app); 
app.use(express.static(publicPath)); 


console.log(`${new Date()} server is up`);
const startServer = async () => {
  set_tronWeb();
  console.log(`Setting up willFactorySC`); 
  willFactorySC = await tronWeb.contract(willFactoryAbi, willFactoryAddress);
  console.log('willFactorySC is set');
  

  const startProcess = async () => {
        const blockNum = (await tronWeb.trx.getCurrentBlock()).block_header.raw_data.number;
        console.log(`${new Date()} Starting Will Inpections at: ${blockNum}`);


        const numOfWills  = await willFactorySC.willsAddressesLength().call();
        if (numOfWills>0)
        {
          console.log(`Found Wills. Starting Will Inpections`);
          for (let i=0; i<numOfWills; i++)
          {
            const will_Address  = tronWeb.address.fromHex(await willFactorySC.willsAddresses(i).call());
            console.log(`Checking will_Address: ${will_Address}`);
            
            const willSC  = await tronWeb.contract(willAbi, will_Address);
            console.log(`Connectted to Will SC at ${will_Address}`);

            const willAdmin  = await willSC.willAdmin().call();
            console.log(`willAdmin: ${tronWeb.address.fromHex(willAdmin)}`);

            const willState  = await willSC.willState().call();
            console.log(`willState: ${willState}`);



            if (willState)
            {
              console.log(`Check Admin Balance`);
              willSC.checkAdminBalance().send({
                feeLimit:2000000000,
                callValue: 0,
                shouldPollResponse:true
              })
              .then(async (res) => {
                  console.log(`Server checked Will Admin Balance. Will now check Will Stage`);

                  willSC.checkWillStage().send({
                    feeLimit:2222000000,
                    callValue: 0,
                    shouldPollResponse:true
                  })
                  .then(async (res) => {
                    console.log(`Server checked Will Stage`);
                  })
                  .catch((error) => console.log(`And error was thrown while will.checkWillStage was called error: `,error));
              
              })
              .catch((error) => console.log(`And error was thrown while will.checkAdminBalance was called error: `,error));


            } else console.log(`Will at ${will_Address} is Active: ${willState}`); 

          }

        } else console.log(`No Wills found`);

        console.log(`Finished checking wills`);
  }  


  setInterval(() => {
    startProcess()
  },30000);

}
startServer();


server.listen(port, () => {
  console.log(`Tron HeartBeat Server is up on port ${port}`);
});