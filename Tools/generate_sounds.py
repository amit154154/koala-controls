"""Generate Koala's original CC0-style procedural sound pack using only Python stdlib.

Legacy MapleStory filenames are retained as internal compatibility identifiers;
these are newly synthesized waves, not recordings or samples from any game.
"""
from pathlib import Path
import math, wave, struct
ROOT=Path(__file__).resolve().parent.parent
RATE=22050

def samples(index):
    level=index in (1,11)
    notes=([523.25,659.25,783.99,1046.5] if index==1 else [392,523.25,659.25,783.99,1046.5]) if level else [360+index*33,540+index*27]
    step=.095 if level else .045
    for f in notes:
        for i in range(int(step*RATE)):
            t=i/RATE;x=t/step;envelope=min(1,x*14)*(1-x)**1.6
            v=math.sin(2*math.pi*f*t)+.16*math.sin(2*math.pi*f*2*t)
            yield int(max(-1,min(1,v*.18*envelope))*32767)

def main():
    for i in range(1,15):
        data=b''.join(struct.pack('<h',v) for v in samples(i))
        for folder in ['Resources/MapleStorySounds','Resources/PhoneRemote/sounds']:
            path=ROOT/folder/f'Maplestory-{i:03}.wav';path.parent.mkdir(parents=True,exist_ok=True)
            with wave.open(str(path),'wb') as f:f.setnchannels(1);f.setsampwidth(2);f.setframerate(RATE);f.writeframes(data)
    print('Generated 14 original Koala sounds in both native and phone packs.')
if __name__=='__main__':main()
