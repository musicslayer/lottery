//interface Result extends ReadonlyArray<any> {
class Result extends Array<any> {
    [key: string]: any;
}

class Rectangle {
    prop;
    args: Result;
    constructor() {
        this.prop = 44;
        this.args = new Result();
        this.args[0] = "A";
        this.args[1] = "B";
        this.args[2] = "C";
        this.args[3] = {"x":"y"};
    }
}

let R = new Rectangle();
//R.args = [{"a":"abc"},{"x":"xyz"}];
//R.args = {"a":"abc"} : 1;

console.log(R);