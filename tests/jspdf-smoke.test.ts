import test from 'node:test';
import assert from 'node:assert/strict';
import {jsPDF} from 'jspdf';

// Smoke test only: full UI/download behavior still requires a real browser.
test('patched jsPDF creates a readable PDF without external files',()=>{
 const doc=new jsPDF({unit:'mm',format:'a4'});
 doc.setFontSize(16);
 doc.text('Escala de Coroinhas - Homologacao',15,20);
 doc.text('Missa: 14/11/2026',15,35);
 doc.text('Funcao: Coroinha',15,45);
 const data=doc.output('arraybuffer');
 const prefix=String.fromCharCode(...new Uint8Array(data).slice(0,8));
 assert.match(prefix,/^%PDF-/);
 assert.ok(data.byteLength>500);
 assert.equal(doc.getNumberOfPages(),1);
});
