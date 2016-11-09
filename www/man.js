/* The following functions are part of a minimal JS library I wrote for VNDB.org */

var expanded_icon = '▾';
var collapsed_icon = '▸';

var http_request = false;
function ajax(url, func, async) {
  if(!async && http_request)
    http_request.abort();
  var req = (window.ActiveXObject) ? new ActiveXObject('Microsoft.XMLHTTP') : new XMLHttpRequest();
  if(req == null)
    return alert("Your browser does not support the functionality this website requires.");
  if(!async)
    http_request = req;
  req.onreadystatechange = function() {
    if(!req || req.readyState != 4 || !req.responseText)
      return;
    if(req.status != 200)
      return alert('Whoops, error! :(');
    func(req);
  };
  url += (url.indexOf('?')>=0 ? ';' : '?')+(Math.floor(Math.random()*999)+1);
  req.open('GET', url, true);
  req.send(null);
}

function byId(n) {
  return document.getElementById(n)
}
function byName(){
  var d = arguments.length > 1 ? arguments[0] : document;
  var n = arguments.length > 1 ? arguments[1] : arguments[0];
  return d.getElementsByTagName(n);
}
function byClass() { // [class], [parent, class], [tagname, class], [parent, tagname, class]
  var par = typeof arguments[0] == 'object' ? arguments[0] : document;
  var t = arguments.length == 2 && typeof arguments[0] == 'string' ? arguments[0] : arguments.length == 3 ? arguments[1] : '*';
  var c = arguments[arguments.length-1];
  var l = byName(par, t);
  var ret = [];
  for(var i=0; i<l.length; i++)
    if(hasClass(l[i], c))
      ret[ret.length] = l[i];
  return ret;
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
function addBody(el) {
  if(document.body.appendChild)
    document.body.appendChild(el);
  else if(document.documentElement.appendChild)
    document.documentElement.appendChild(el);
  else if(document.appendChild)
    document.appendChild(el);
}
function setContent() {
  setText(arguments[0], '');
  for(var i=1; i<arguments.length; i++)
    if(arguments[i] != null)
      arguments[0].appendChild(tag(arguments[i]));
}
function getText(obj) {
  return obj.textContent || obj.innerText || '';
}
function setText(obj, txt) {
  if(obj.textContent != null)
    obj.textContent = txt;
  else
    obj.innerText = txt;
}

function listClass(obj) {
  var n = obj.className;
  if(!n)
    return [];
  return n.split(/ /);
}
function hasClass(obj, c) {
  var l = listClass(obj);
  for(var i=0; i<l.length; i++)
    if(l[i] == c)
      return true;
  return false;
}
function setClass(obj, c, set) {
  var l = listClass(obj);
  var n = [];
  if(set) {
    n = l;
    if(!hasClass(obj, c))
      n[n.length] = c;
  } else {
    for(var i=0; i<l.length; i++)
      if(l[i] != c)
        n[n.length] = l[i];
  }
  obj.className = n.join(' ');
}


// Dropdown Search

function dsInit(obj, url, trfunc, serfunc, retfunc, parfunc) {
  obj.setAttribute('autocomplete', 'off');
  obj.onkeydown = dsKeyDown;
  obj.onblur = function() { setTimeout(function () { setClass(byId('ds_box'), 'hidden', true) }, 250) };
  obj.ds_returnFunc = retfunc;
  obj.ds_trFunc = trfunc;
  obj.ds_serFunc = serfunc;
  obj.ds_parFunc = parfunc;
  obj.ds_searchURL = url;
  obj.ds_selectedId = 0;
  obj.ds_dosearch = null;
  if(!byId('ds_box'))
    addBody(tag('div', {id: 'ds_box', 'class':'hidden'}, tag('b', 'Loading...')));
}

function dsKeyDown(ev) {
  var c = document.layers ? ev.which : document.all ? event.keyCode : ev.keyCode;
  var obj = this;

  if(c == 9) // tab
    return true;

  // do some processing when the enter key has been pressed
  if(c == 13) {
    var frm = obj;
    while(frm && frm.nodeName.toLowerCase() != 'form')
      frm = frm.parentNode;
    if(frm) {
      var oldsubmit = frm.onsubmit;
      frm.onsubmit = function() { return false };
      setTimeout(function() { frm.onsubmit = oldsubmit }, 100);
    }

    if(obj.ds_selectedId != 0)
      obj.value = obj.ds_serFunc(byId('ds_box_'+obj.ds_selectedId).ds_itemData, obj);
    if(obj.ds_returnFunc)
      obj.ds_returnFunc(obj);

    setClass(byId('ds_box'), 'hidden', true);
    setContent(byId('ds_box'), tag('b', 'Loading...'));
    obj.ds_selectedId = 0;
    if(obj.ds_dosearch) {
      clearTimeout(obj.ds_dosearch);
      obj.ds_dosearch = null;
    }

    return false;
  }

  // process up/down keys
  if(c == 38 || c == 40) {
    var l = byName(byId('ds_box'), 'tr');
    if(l.length < 1)
      return true;

    // get new selected id
    if(obj.ds_selectedId == 0) {
      if(c == 38) // up
        obj.ds_selectedId = l[l.length-1].id.substr(7);
      else
        obj.ds_selectedId = l[0].id.substr(7);
    } else {
      var sel = null;
      for(var i=0; i<l.length; i++)
        if(l[i].id == 'ds_box_'+obj.ds_selectedId) {
          if(c == 38) // up
            sel = i>0 ? l[i-1] : l[l.length-1];
          else
            sel = l[i+1] ? l[i+1] : l[0];
        }
      obj.ds_selectedId = sel.id.substr(7);
    }

    // set selected class
    for(var i=0; i<l.length; i++)
      setClass(l[i], 'selected', l[i].id == 'ds_box_'+obj.ds_selectedId);
    return true;
  }

  // perform search after a timeout
  if(obj.ds_dosearch)
    clearTimeout(obj.ds_dosearch);
  obj.ds_dosearch = setTimeout(function() {
    dsSearch(obj);
  }, 500);

  return true;
}

function dsSearch(obj) {
  var box = byId('ds_box');
  var val = obj.ds_parFunc ? obj.ds_parFunc(obj.value) : obj.value;

  clearTimeout(obj.ds_dosearch);
  obj.ds_dosearch = null;

  // hide the ds_box div
  if(val.length < 2) {
    setClass(box, 'hidden', true);
    setContent(box, tag('b', 'Loading...'));
    obj.ds_selectedId = 0;
    return;
  }

  // position the div
  var ddx=0;
  var ddy=obj.offsetHeight;
  var o = obj;
  do {
    ddx += o.offsetLeft;
    ddy += o.offsetTop;
  } while(o = o.offsetParent);

  box.style.position = 'absolute';
  box.style.left = ddx+'px';
  box.style.top = ddy+'px';
  box.style.width = obj.offsetWidth+'px';
  setClass(box, 'hidden', false);

  // perform search
  ajax(obj.ds_searchURL + encodeURIComponent(val), function(hr) {
    dsResults(hr, obj);
  });
}

function dsResults(hr, obj) {
  var lst = hr.responseXML.getElementsByTagName('item');
  var box = byId('ds_box');
  if(lst.length < 1) {
    setContent(box, tag('b', 'No results'));
    obj.selectedId = 0;
    return;
  }

  var tb = tag('tbody', null);
  for(var i=0; i<lst.length; i++) {
    var id = lst[i].getAttribute('id');
    var tr = tag('tr', {id: 'ds_box_'+id, ds_itemData: lst[i]} );
    setClass(tr, 'selected', obj.selectedId == id);

    tr.onmouseover = function() {
      obj.ds_selectedId = this.id.substr(7);
      var l = byName(box, 'tr');
      for(var j=0; j<l.length; j++)
        setClass(l[j], 'selected', l[j].id == 'ds_box_'+obj.ds_selectedId);
    };
    tr.onmousedown = function() {
      obj.value = obj.ds_serFunc(this.ds_itemData, obj);
      if(obj.ds_returnFunc)
        obj.ds_returnFunc();
      setClass(box, 'hidden', true);
      obj.ds_selectedId = 0;
    };

    obj.ds_trFunc(lst[i], tr);
    tb.appendChild(tr);
  }
  setContent(box, tag('table', tb));

  if(obj.ds_selectedId != 0 && !byId('ds_box_'+obj.ds_selectedId))
    obj.ds_selectedId = 0;
}





/* What follows is specific to manned.org */

// Search box
(function(){
  searchRedir = false;
  dsInit(byId('q'), '/xml/search.xml?q=', function(item, tr) {
      tr.appendChild(tag('td', item.getAttribute('name'), tag('i', '('+item.getAttribute('section')+')')));
    },
    function(item) {
      searchRedir = true;
      location.href = '/'+item.getAttribute('name')+'.'+item.getAttribute('section');
      return item.getAttribute('name')+'('+item.getAttribute('section')+')';
    },
    function() {
      if(!searchRedir) {
        var frm=byId('q');
        while(frm && frm.nodeName.toLowerCase() != 'form')
          frm = frm.parentNode;
        frm.submit();
      }
    }
  );
})();





// The tabs on man pages
(function(){
  var ul = byId('manbuttons');
  if(!ul)
    return;
  var res = byId('manres');
  ul = byName(ul, 'ul')[0];


  var table = function(tbl, prop) {
    var t = tag('table', prop);
    for(row in tbl) {
      row = tbl[row];
      var r = tag('tr', {});
      for(col in row) {
        col = row[col];
        r.appendChild(tag('td',
          col.bold ? tag('b', col.name) :
          col.href ? tag('a', {href:col.href}, col.name) : col.name
        ));
      }
      t.appendChild(r);
    }
    return t;
  };

  var treeoldver = function() {
    var lnk = this;
    var ul = lnk;
    var show = !lnk['data-shown'];
    lnk['data-shown'] = show;

    while(ul.nodeName.toLowerCase() != 'ul')
      ul = ul.parentNode;
    var l = ul.childNodes;
    for(var i=0; i<l.length; i++) {
      if(l[i].nodeName.toLowerCase() == 'li' && l[i]['data-oldver'])
        setClass(l[i], 'hidden', !show);
    }

    setText(lnk, (show ? '- ' : '+ ')+lnk['data-hidnum']+' older versions');
    return false;
  };

  var treeexpand = function() {
    var sub = byName(this.parentNode, 'ul')[0] || byName(this.parentNode, 'table')[0];
    var exp = hasClass(sub, 'hidden');
    setClass(sub, 'hidden', !exp);
    setText(this, getText(this).replace(/^[^ ]+/, exp ? expanded_icon : collapsed_icon));
    return false;
  };

  var treeitem = function(n) {
    var icon = n.name ? (n.expand ? expanded_icon : collapsed_icon)+' ' : '';
    return tag('li', n.hide ? {'class':'hidden', 'data-oldver':true} : {},
       tag('a', {href:'#', onclick: treeexpand}, icon+n.name),
       n.i ? tag('i', n.i) : null,
       n.childs ? treelist(n.childs, n.expand ? {} : {'class':'hidden'}) : null,
       n.table ? table(n.table, n.expand ? {} : {'class':'hidden'}) : null
    );
  };

  var treelist = function(lst, prop) {
    var ul = tag('ul', prop);
    var hidden = 0;

    for(i in lst) {
      var n = lst[i];
      if(n.hide)
        hidden++;
      ul.appendChild(treeitem(lst[i]));
    }

    if(hidden > 0)
      ul.appendChild(tag('li', {'class':'oldver'},
        tag('a', {href:'#', onclick: treeoldver, 'data-hidnum':hidden}, '+ '+hidden+' older versions')
      ));
    return ul;
  };

  var clearactive = function() {
    setClass(res, 'hidden', true);
    var l = byName(ul, 'a');
    for(var i=0; i<l.length; i++) {
      setClass(l[i], 'active', false);
      if(l[i]['data-obj'])
        setClass(l[i]['data-obj'], 'hidden', true);
    }
    return false;
  };

  var loading = tag('div', {'class':'hidden'}, 'Loading...');

  var buttonclick = function() {
    var btn = this;
    var isactive = hasClass(btn, 'active');
    clearactive();
    if(isactive)
      return false;

    if(btn['data-obj']) {
      setClass(btn['data-obj'], 'hidden', false);
    } else {
      setClass(loading, 'hidden', false);
      ajax(btn['data-url'], function(r) {
        setClass(loading, 'hidden', true);
        r = JSON.parse(r.responseText);
        btn['data-obj'] = tag('div', tag('p', btn['data-p']), treelist(r, {}));
        res.appendChild(btn['data-obj']);
      });
    }
    setClass(btn, 'active', true);
    setClass(res, 'hidden', false);
    return false;
  };

  res.insertBefore(tag('a', {id:'closebtn', href:'#', onclick: clearactive}, 'X'), res.firstChild);
  res.appendChild(loading);

  (function(){
    var name = ul.getAttribute('data-name');
    var hash = ul.getAttribute('data-hash');
    var section = ul.getAttribute('data-section');
    var locale = ul.getAttribute('data-locale');

    ul.appendChild(tag('li', ul.getAttribute('data-hasversions') > 0
      ? tag('a', {href:'#', onclick: buttonclick,
          'data-url': '/json/tree.json?name='+name+';section='+section+';locale='+locale+';cur='+hash,
          'data-p': 'Different versions of this manual page are available.'},
          'versions')
      : tag('i', 'versions')
    ));

    ul.appendChild(tag('li', tag('a', {href:'#', onclick: buttonclick,
      'data-url': '/json/tree.json?hash='+hash+';name='+name+';section='+section,
      'data-p': 'This manual page was found in the following locations.'},
      'locations')));
  })();
})();




// The "more..." links on the homepage.
(function(){
  var sys = byId('systems');
  if(!sys)
    return;
  var f = function() {
    var l = byName(this.parentNode, 'a');
    var show = hasClass(l[3], 'hidden');
    for(var i=3; i<l.length-1; i++)
      setClass(l[i], 'hidden', !show);
    setText(this, show ? '...less' : 'more...');
    return false
  };
  var l = byClass(sys, 'a', 'more');
  for(var i=0; i<l.length; i++)
    l[i].onclick = f;
})();
