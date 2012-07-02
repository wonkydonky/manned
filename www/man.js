/* The following functions are part of a minimal JS library I wrote for VNDB.org */

function byId(n) {
  return document.getElementById(n)
}

/* wrapper around DOM element creation
 * tag('string') -> createTextNode
 * tag('tagname', tag(), 'string', ..) -> createElement(), appendChild(), ..
 * tag('tagname', { class: 'meh', title: 'Title' }) -> createElement(), setAttribute()..
 * tag('tagname', { <attributes> }, <elements>) -> create, setattr, append */
function tag() {
  if(arguments.length == 1)
    return typeof arguments[0] != 'object' ? document.createTextNode(arguments[0]) : arguments[0];
  var el = typeof document.createElementNS != 'undefined'
    ? document.createElementNS('http://www.w3.org/1999/xhtml', arguments[0])
    : document.createElement(arguments[0]);
  for(var i=1; i<arguments.length; i++) {
    if(arguments[i] == null)
      continue;
    if(typeof arguments[i] == 'object' && !arguments[i].appendChild) {
      for(attr in arguments[i]) {
        if(attr == 'style')
          el.setAttribute(attr, arguments[i][attr]);
        else
          el[ attr == 'class' ? 'className' : attr == 'for' ? 'htmlFor' : attr ] = arguments[i][attr];
      }
    } else
      el.appendChild(tag(arguments[i]));
  }
  return el;
}



/* What follows is specific to manned.org */

if(byId('nav')) {
  var nav = byId('nav');
  for(var i=0; i<VARS.mans.length; i++) {
    var dt = tag('dt', VARS.mans[i][1]);
    var dd = tag('dd', null);
    for(var j=0; j<VARS.mans[i][2].length; j++) {
      var pkg = VARS.mans[i][2][j];
      var pdt = tag('dt', pkg[0], tag('i', pkg[1]));
      var pdd = tag('dd', null);
      for(var k=0; k<pkg[2].length; k++) {
        var man = pkg[2][k];
        var txt = man[0] + (man[1] ? '.'+man[1] : '');
        if(k > 0)
          pdd.appendChild(tag(' '));
        pdd.appendChild(man[2] == VARS.hash ? tag('b', txt) : tag('a', {href:'/'+VARS.name+'/'+man[2]}, txt));
      }
      dd.appendChild(pdt);
      dd.appendChild(pdd);
    }
    nav.appendChild(dt);
    nav.appendChild(dd);
  }
}

