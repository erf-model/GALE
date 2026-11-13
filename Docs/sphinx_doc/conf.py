# Sphinx configuration for GALE's documentation (https://erf-model.github.io/GALE/).
# ERF's own documentation is at https://erf.readthedocs.io; these pages cover only what GALE adds.

project = 'GALE'
author = 'GALE and ERF developers'
copyright = ' '
version = ''
release = ''
language = 'en'

extensions = [
    'sphinx.ext.mathjax',
    'sphinx_copybutton',
]

master_doc = 'index'
source_suffix = '.rst'
exclude_patterns = ['_build']
numfig = True
numfig_format = {'figure': '%s', 'table': '%s', 'code-block': '%s'}

html_theme = 'sphinx_rtd_theme'
html_title = 'GALE documentation'
