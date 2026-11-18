"""Retrieval-inference evaluation: final scores use only the last round."""
def evaluate(run, args):
    if __package__:
        from .evaluation import build
    else:
        from evaluation import build
    return build(run, 'infer', args)
