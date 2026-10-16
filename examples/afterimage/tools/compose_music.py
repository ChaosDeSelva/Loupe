"""Three original stereo space-synth compositions. MIT. Python standard library only.
Run this script, then encode WAV outputs to OGG with FFmpeg (see README).
"""
import array
import math
import random
import wave
from pathlib import Path

RATE = 22050
TRACKS = [('glasslight', 100, 0), ('violet-current', 108, 5), ('ember-orbit', 116, 7)]
CHORDS = [[50,57,62,65], [46,53,58,62], [41,53,57,60], [48,55,60,64]]
MELODY = [[74,77,81,77,74,72,69,72], [70,74,77,74,70,69,65,69],
          [69,72,77,72,69,67,65,67], [72,76,79,76,72,70,67,69]]

def compose(name, bpm, transpose):
    beat = 60 / bpm
    count = int(RATE * beat * 64)
    left, right = array.array('f', [0]) * count, array.array('f', [0]) * count
    rng = random.Random(4242 + transpose)

    def note(start, beats, midi, volume, voice='lead', pan=0):
        freq = 440 * 2 ** ((midi + transpose - 69) / 12)
        length, offset = int(beats * beat * RATE), int(start * beat * RATE)
        for i in range(length):
            t, progress = i / RATE, i / length
            attack = min(1, t / (.18 if voice == 'pad' else .012))
            envelope = attack * (1-progress) ** (1 if voice == 'pad' else 1.8)
            phase = 2 * math.pi * freq * t
            tone = math.sin(phase) + .15*math.sin(phase*2)
            if voice == 'pad': tone = (math.sin(phase)+math.sin(phase*1.003)+math.sin(phase*.997))/3
            if voice == 'bass': tone = math.sin(phase)+.25*math.sin(phase*.5)
            value = tone * envelope * volume
            j = (offset+i) % count
            left[j] += value*(1-pan*.6); right[j] += value*(1+pan*.6)
            if voice in ('lead', 'pad'):
                left[(j+int(beat*.75*RATE)) % count] += value*.25
                right[(j+int(beat*1.25*RATE)) % count] += value*.25
    for bar in range(16):
        chord = CHORDS[(bar + transpose % 4) % 4]
        for j,pitch in enumerate(chord): note(bar*4,5,pitch,.10,'pad',(j-1.5)/2)
        for k in range(8):
            note(bar*4+k*.5,.45,chord[0]-12,.16,'bass')
            pitch = MELODY[bar%4][k] + (12 if bar>=8 and k%4==2 else 0)
            note(bar*4+k*.5,.65,pitch,.10,'lead',math.sin(k*.7)*.6)
        if bar%4==3: note(bar*4,3,86,.045,'lead',-.4)
    for n in range(64):
        start = int(n*beat*RATE)
        for i in range(int(.20*RATE)):
            t=i/RATE
            kick=math.sin(2*math.pi*(70*t-65*t*t))*math.exp(-t*23)*.26
            left[(start+i)%count]+=kick;right[(start+i)%count]+=kick
        if n%2==1:
            for i in range(int(.13*RATE)):
                t=i/RATE;noise=(rng.random()*2-1)*math.exp(-t*32)*.09
                left[(start+i)%count]+=noise;right[(start+i)%count]+=noise
    # Master each piece to a consistent peak with headroom for game effects.
    peak=max(max(abs(x) for x in left),max(abs(x) for x in right))
    gain=.88/max(.01,peak)
    pcm=array.array('h')
    for l,r in zip(left,right): pcm.extend((int(l*gain*32767),int(r*gain*32767)))
    out=Path(__file__).resolve().parents[1]/'assets'/f'{name}.wav'
    with wave.open(str(out),'wb') as output:
        output.setnchannels(2);output.setsampwidth(2);output.setframerate(RATE);output.writeframes(pcm.tobytes())
    print(out, flush=True)

if __name__ == '__main__':
    for track in TRACKS: compose(*track)
