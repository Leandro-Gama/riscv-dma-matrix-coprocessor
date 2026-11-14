# Plano de Verificação: compila o PDF com pdflatex (3 passadas: sumário e referências cruzadas).
DOC   := plano_de_verificacao
TEX   := pdflatex -interaction=nonstopmode -halt-on-error

.PHONY: pdf clean

pdf: $(DOC).pdf

$(DOC).pdf: $(DOC).tex
	$(TEX) $(DOC).tex >/dev/null
	$(TEX) $(DOC).tex >/dev/null
	$(TEX) $(DOC).tex
	@grep -c "^!" $(DOC).log >/dev/null && (echo "ERROS no log"; exit 1) || echo "OK: $(DOC).pdf"

clean:
	rm -f $(DOC).aux $(DOC).log $(DOC).out $(DOC).toc $(DOC).lof $(DOC).lot
