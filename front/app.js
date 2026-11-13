// ===================== FRONT: lo que reacciona (JavaScript) =====================
// Este archivo corre en el navegador de Camila. Cualquiera lo puede ver con F12:
// por eso aquí NO van las instrucciones del modelo, ni el catálogo "de verdad", ni claves.
// La página solo manda la charla al BACK; el BACK es el que habla con Amazon Bedrock.
var BACK = window.CHAT_URL; // la dirección de tu Lambda (la escribe Terraform en config.js)
var CUPO = 12;              // cuántos mensajes viajan como máximo en cada pregunta

var CATALOGO = [
  { id: "camiseta", nombre: "Camiseta Laura", texto: "Algodón peinado, corte relajado.", precio: 59000, color: "#59c3ff", fondo: "#e3f4ff" },
  { id: "gorra", nombre: "Gorra Laura", texto: "Visera curva, ajuste trasero.", precio: 39000, color: "#16182b", fondo: "#efeefe" },
  { id: "buzo", nombre: "Buzo Laura", texto: "Felpa gruesa con capota.", precio: 119000, color: "#ff7aa8", fondo: "#ffe8f0" }
];

var $ = function (id) { return document.getElementById(id); };
var pesos = function (n) { return "$" + Number(n || 0).toLocaleString("es-CO"); };
var charla = [], ocupado = false, gastados = 0;

// ---------- la colección: toca una prenda y Lau te cuenta ----------
$("productos").innerHTML = CATALOGO.map(function (p) {
  return '<button type="button" class="producto" data-id="' + p.id + '">' +
    '<div class="producto-foto" style="background:' + p.fondo + '"><svg viewBox="0 0 220 220" style="color:' + p.color + '"><use href="#ico-' + p.id + '"/></svg></div>' +
    "<h3>" + p.nombre + "</h3><p>" + p.texto + "</p>" +
    '<div class="precio">' + pesos(p.precio) + "<span>pregúntale a Lau</span></div></button>";
}).join("");
document.querySelectorAll(".producto").forEach(function (b) {
  b.addEventListener("click", function () {
    $("lau").scrollIntoView();
    preguntar("Cuéntame de " + (b.dataset.id === "gorra" ? "la gorra" : "el " + b.dataset.id) + ": precio, tallas y colores.");
  });
});

// ---------- el viaje de la pregunta (animación de los 5 pasos) ----------
var pasos = document.querySelectorAll("#pasos li");
function marcar(n) {
  pasos.forEach(function (li, i) { li.classList.toggle("activo", i === n); li.classList.toggle("hecho", i < n); });
}
function terminar() { pasos.forEach(function (li) { li.classList.remove("activo"); li.classList.add("hecho"); }); }
function limpiarPasos() { pasos.forEach(function (li) { li.classList.remove("activo", "hecho"); }); }

function medir(r, total) {
  $("m-entrada").textContent = r.tokens.entrada;
  $("m-salida").textContent = r.tokens.salida;
  $("m-ms").textContent = r.ms + " ms";
  $("m-total").textContent = total + " ms";
  gastados += r.tokens.entrada + r.tokens.salida;
  $("detalle").textContent = "modelo " + r.modelo + " · temperatura " + r.temperatura + " · tokens de esta charla: " + gastados.toLocaleString("es-CO");
}
function mochila() {
  var n = Math.min(charla.length, CUPO), h = "";
  for (var i = 0; i < CUPO; i++) h += i < n ? '<i class="lleno"></i>' : "<i></i>";
  $("mochila").innerHTML = h;
  $("cupo").textContent = n + " de " + CUPO;
}

// ---------- el chat ----------
function burbuja(clase, texto) {
  var d = document.createElement("div"); d.className = clase; d.textContent = texto;
  $("hilo").appendChild(d); $("hilo").scrollTop = $("hilo").scrollHeight; return d;
}
function saludo() {
  $("hilo").innerHTML = "";
  burbuja("msj lau", "Hola, soy Lau, la asistente de la tienda. Pregúntame por productos, precios, tallas, envíos o cambios.");
}

// hablar con el BACK: se manda TODA la charla (hasta 12 mensajes), no solo la última pregunta
function preguntar(texto) {
  texto = String(texto || "").trim();
  if (!texto || ocupado) return;
  if (!BACK) { burbuja("msj falla", "Falta config.js: esta página debe abrirse desde tu_tienda (CloudFront)."); return; }
  ocupado = true; $("enviar").disabled = true; $("caja").value = "";
  burbuja("msj yo", texto);
  charla.push({ rol: "user", texto: texto });
  mochila();
  var espera = burbuja("puntos", ""); espera.innerHTML = "<i></i><i></i><i></i>";
  var t0 = performance.now();
  marcar(0);
  setTimeout(function () { marcar(1); }, 200);
  setTimeout(function () { marcar(2); }, 450);
  setTimeout(function () { if (ocupado) marcar(3); }, 700);

  fetch(BACK, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ mensajes: charla.slice(-CUPO) }) })
    .then(function (r) { return r.json().then(function (j) { return { ok: r.ok, j: j }; }); })
    .then(function (r) {
      espera.remove();
      if (!r.ok) {
        charla.pop(); limpiarPasos();
        burbuja("msj falla", "El modelo no respondió · " + r.j.error + (r.j.detalle ? "\n" + r.j.detalle : ""));
        return;
      }
      var total = Math.round(performance.now() - t0);
      marcar(4); setTimeout(terminar, 350);
      burbuja("msj lau", r.j.texto);
      burbuja("nota", r.j.tokens.entrada + " tokens de entrada · " + r.j.tokens.salida + " de salida");
      charla.push({ rol: "assistant", texto: r.j.texto });
      medir(r.j, total);
    })
    .catch(function () {
      espera.remove(); charla.pop(); limpiarPasos();
      burbuja("msj falla", "No hubo conexión con el back. Revisa que terraform apply haya terminado.");
    })
    .then(function () { ocupado = false; $("enviar").disabled = false; mochila(); });
}

$("forma").addEventListener("submit", function (e) { e.preventDefault(); preguntar($("caja").value); });
$("atajos").addEventListener("click", function (e) { if (e.target.tagName === "BUTTON") preguntar(e.target.textContent); });
$("nuevo").addEventListener("click", function () { charla = []; gastados = 0; limpiarPasos(); saludo(); mochila(); });
saludo(); mochila();
