import { world } from "@minecraft/server";

world.afterEvents.playerSpawn.subscribe((event) => {
  const player = event.player;

  if (event.initialSpawn) {
    player.sendMessage("Hello World!");
  }
});
