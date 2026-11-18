"""Run the game:  python3 -m odyssey [--scale N] [--no-sound] [--save FILE]"""
import argparse
import random
import sys


def main(argv=None):
    ap = argparse.ArgumentParser(prog='odyssey', description='Odyssey: The Compleat Apventure (1980), in Python.')
    ap.add_argument('--scale', type=int, default=3, help='window size as a multiple of 280x192 (default 3)')
    ap.add_argument('--no-sound', action='store_true', help='keep the speaker quiet')
    ap.add_argument('--save', default='odyssey-old-game.json', metavar='FILE',
                    help="where the 'OLD GAME' is saved (default: %(default)s)")
    ap.add_argument('--seed', type=int, help='seed the random numbers (for repeatable games)')
    args = ap.parse_args(argv)

    try:
        from .screen import Window
    except ImportError:
        sys.exit('Odyssey needs pygame-ce:  pip install pygame-ce')
    from .apple import Quit
    from .game import Game

    window = Window(scale=args.scale, sound=not args.no_sound)
    rng = random.Random(args.seed) if args.seed is not None else None
    game = Game(window, save_path=args.save, rng=rng)
    try:
        game.run()
    except (Quit, KeyboardInterrupt):
        pass
    finally:
        import pygame
        pygame.quit()


if __name__ == '__main__':
    main()
