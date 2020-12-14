# Node-red

The node red installation requires several node modules:

* striptags
* zuzel-printer
* onoff
* node-red-contrib-aws-sdk
* node-red-node-pi-gpio
* node-red-node-ping

It also requires the `settings.js` file to be loaded into the .node-red directory. You will need to import the contents of `flow.json` into the workspace.

# Running locally

1. Run the node-red docker images and install the node-modules:

```bash
docker run -it -p 1880:1880 --entrypoint /bin/sh -v $HOME/dumpster-fire-2020/node-red:/data --name mynodered nodered/node-red
> cd /data
> npm install
> Ctrl-D
docker stop mynodered; docker rm mynodered
docker run -it -p 1880:1880 -v $HOME/dumpster-fire-2020/node-red:/data --name mynodered nodered/node-red
```
2. Pull up in browser: http://localhost:1880/
