# Sphinx configuration for GALE's documentation (https://erf-model.github.io/GALE/).
# ERF's own documentation is at https://erf.readthedocs.io; these pages cover only what GALE adds.

project = 'GALE'
author = 'GALE and ERF developers'
copyright = 'GALE and ERF developers'
version = ''
release = ''
language = 'en'

extensions = [
    'sphinx.ext.mathjax',
    'sphinx_copybutton',
    'sphinx_design',
]

master_doc = 'index'
source_suffix = '.rst'
exclude_patterns = ['_build']
numfig = True
numfig_format = {'figure': 'Figure %s', 'table': 'Table %s', 'code-block': 'Listing %s'}

html_theme = 'furo'
html_title = 'GALE'
html_static_path = ['_static']
html_css_files = ['gale.css']
html_theme_options = {
    'source_repository': 'https://github.com/erf-model/GALE/',
    'source_branch': 'development',
    'source_directory': 'Docs/sphinx_doc/',
    'navigation_with_keys': True,
    'light_css_variables': {
        'color-brand-primary': '#0b6e8a',
        'color-brand-content': '#0b6e8a',
    },
    'dark_css_variables': {
        'color-brand-primary': '#4fc3dc',
        'color-brand-content': '#4fc3dc',
    },
}
