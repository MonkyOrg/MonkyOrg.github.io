// Manda o visitante para o idioma do navegador na primeira visita, e sai do
// caminho assim que ele escolher um idioma na mao.
//
// A chave do localStorage e a mesma que a documentacao usa (`monky-lang-manual`,
// definida no head do VitePress em docs-site/.vitepress/config.ts). As duas
// vivem no dominio monkyorg.github.io, entao o localStorage e compartilhado: quem
// trocou o idioma na documentacao chega aqui e nao e mandado de volta para o
// idioma do sistema.
//
// Roda antes de qualquer coisa ser desenhada, senao o visitante veria a pagina
// errada piscar antes do redirecionamento.
(function () {
  var isEn = /^\/en(\/|$)/.test(location.pathname);

  try {
    if (!localStorage.getItem('monky-lang-manual')) {
      var wantsPt = (navigator.language || '').toLowerCase().indexOf('pt') === 0;
      if (wantsPt && isEn) { location.replace('/'); return; }
      if (!wantsPt && !isEn) { location.replace('/en/'); return; }
    }
  } catch (e) {
    // Navegador com storage bloqueado: fica na pagina em que chegou, que e
    // melhor do que redirecionar de novo a cada visita.
  }

  document.addEventListener('click', function (e) {
    if (e.target.closest && e.target.closest('.translations')) {
      try { localStorage.setItem('monky-lang-manual', '1'); } catch (err) {}
    }
  });
})();
