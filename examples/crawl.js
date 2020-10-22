(() => {
	function f(q) {
		return $(q + ' .task-group').toArray().map((x) => [...x.children].map((y) => y.textContent).filter((y) => y != "").map((y) => Number(y)));
	}
	return JSON.stringify({v: f('#taskTop'), h: f('#taskLeft') });
})();