# Night sky stuff (I DID NOT MAKE THESE, NASA DID)

Files: `milkyway_8k.png`, `milkyway_4k.png`, `starCatalog.bin`. 
Basically I ran a python script (`tools/nasa_night_sky.py`) to generate these from actual space data. None of this is hand-painted in photoshop or anything. Every single pixel is real starlight. It ain't much but it's honest work. yuh.

## Milky Way texture (`milkyway_8k.png`, `milkyway_4k.png`)

**Source:** NASA's Scientific Visualization Studio, *Deep Star Maps 2020*. 
Visualizer: Ernie Wright. (Shoutout Ernie, what a legend). 
- I used these massive 16k .exr files that had like 1.7 billion stars in them from Gaia DR2 and Tycho-2. 

**Processing shit I had to do:**
- I basically had to write code to cut out the bright stars and slap the rest onto the background.
- Blurry math stuff to make sure the pixels stay square on the sphere (don't ask me how it works, my brain is fried).
- **Note about brightness:** The NASA maps compress the brightness weirdly. The Milky Way glow is like 5 to 15 times brighter than it should be in real life compared to the stars. It looks dope as fuck though, kinda like a long-exposure camera shot. So yeah, the brightness isn't 100% physically accurate, don't @ me. 

## The Star Catalog (`starCatalog.bin`)

- **Hipparcos Main Catalogue:** (Hipparcos sounds like a damn dinosaur lol). Got this from VizieR. It gave me like 41,394 stars.
- **Yale Bright Star Catalogue:** Grabbed 33 extra stars that were missing from the first list.
- The colors are based on real B-V data. I used some crazy formula from Ballesteros (2012) to calculate the temperature and turn it into RGB colors. Big brain shit.

## Licensing (READ THIS SHIT)

- **NASA Stuff:** NASA images are mostly public domain in the US, they just want credit. They definitely don't endorse this Minecraft shader lmao.
- **Gaia Data (ESA):** Okay seriously, the ESA Gaia license is **CC BY-NC 3.0 IGO**. That means NON-COMMERCIAL. If you try to put this shader pack behind a Patreon paywall or sell it on some sketchy website, the European Space Agency might literally come after your ass. You have to ask ESA for permission if you want to make money off this.
- **My Scripts:** The `nasa_night_sky.py` script and the tools I actually coded are MIT licensed, so you can do whatever the fuck you want with my spaghetti code.

(Disclaimer: I am just a loser, not a lawyer. This is not legal advice).